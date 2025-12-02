from abc import ABC, abstractmethod
from typing import Iterator, List, Union, Callable
from tools.ila_generator.utils.token import Token
from tools.ila_generator.utils.symbol_resolver import SymbolResolver
from itertools import tee

class Match(ABC):
    @abstractmethod
    def matches(self, token: Token) -> bool:
        pass

class SymbolIdentifier(Match):
    def __init__(self, text: str = None, callback: Callable[[str], None] = None):
        """
        Calls the callback with the text value if
        text is None and a token is matched!
        """
        super().__init__()
        self.text = text
        self.callback = callback

    def matches(self, token: Token) -> bool:
        if self.text == None:
            if token.is_symbol_identifier():
                if self.callback != None:
                    self.callback(token.get_text())
                return True
            return False
        else:
            return token.is_symbol_identifier() and token.get_text() == self.text

class Dot(Match):
    def __init__(self, single: bool):
        super().__init__()
        self.single = single

    def matches(self, token: Token) -> bool:
        if self.single:
            return token.self_kind_is(".")
        else:
            return token.self_kind_is(":")

class Hashtag(Match):
    def __init__(self):
        super().__init__()

    def matches(self, token: Token) -> bool:
        return token.self_kind_is("#")

class InputDeclaration(Match):
    def __init__(self):
        super().__init__()

    def matches(self, token: Token) -> bool:
        return token.self_kind_is("input")

class OutputDeclaration(Match):
    def __init__(self):
        super().__init__()

    def matches(self, token: Token) -> bool:
        return token.self_kind_is("output")

class Logic(Match):
    def __init__(self):
        super().__init__()

    def matches(self, token: Token) -> bool:
        return token.self_kind_is("logic")

class ArrayParentheses(Match):
    def __init__(self, open):
        super().__init__()
        self.open = open

    def matches(self, token: Token) -> bool:
        if self.open:
            return token.self_kind_is("[")
        else:
            return token.self_kind_is("]")

class Parentheses(Match):
    def __init__(self, open):
        super().__init__()
        self.open = open
    
    def matches(self, token: Token) -> bool:
        if self.open:
            return token.self_kind_is("(")
        else:
            return token.self_kind_is(")")

class Decimal(Match):
    def __init__(self, callback: Callable[[int], None] = None):
        super().__init__()
        self.callback = callback
    
    def matches(self, token: Token) -> bool:
        if token.self_kind_is("TK_DecNumber"):
            if self.callback != None:
                self.callback(int(token.get_text()))
            return True
        else:
            return False

class MathExpression(Match):
    def __init__(self, callback: Callable[[Callable[[int, int], None]], None] = None):
        super().__init__()
        self.callback = callback
    
    def matches(self, token: Token) -> bool:
        if token.self_kind_is("+"):
            if self.callback != None:
                self.callback(lambda x,y: x + y)
            return True
        elif token.self_kind_is("-"):
            if self.callback != None:
                self.callback(lambda x,y: x - y)
            return True
        elif token.self_kind_is("/"):
            if self.callback != None:
                self.callback(lambda x,y: x / y)
            return True
        elif token.self_kind_is("*"):
            if self.callback != None:
                self.callback(lambda x,y: x * y)
            return True
        else:
            return False

class MatchGroup():
    def __init__(self, *args: List[Union[Match, 'MatchGroup', 'OptionalMatchGroup', 'LazyMatchGroup']], name = ""):
        super().__init__()
        self.group_elements = [*args]
        self.name = name

    def number_of_matching_tokens(self, tokens: List[Token], debug=False) -> int:
        """
        Returns the number of tokens this match group managed to match.
          0 = No matches
        > 0 -> Successfully matched all group elements. Number represents
               the total number of matched tokens
        """
        if debug:
            if (self.name):
                print(f"Matching Group: {self.name}")
            else:
                print(f"Matching Group with {len(self.group_elements)} elements")

        index = 0
        for matcher in self.group_elements:
            # Check if we would go out of bounds
            if len(tokens) <= index:
                return 0
           
            if isinstance(matcher, LazyMatchGroup):
                matcher = matcher.infer_matching_group(debug)

            if isinstance(matcher, Match):
                 # A normal matcher matches a single token
                if matcher.matches(tokens[index]):
                    if debug:
                        print(f"Matched token : {str(tokens[index])}")
                    index += 1
                else:
                    return 0
            elif isinstance(matcher, OptionalMatchGroup):
                # We dont check for success here
                # Optional can fail to match!
                rec_matched = matcher.number_of_matching_tokens(tokens[index:], debug)
                index += rec_matched
            elif isinstance(matcher, MatchGroup):
                # A match group can consume multiple tokens!
                rec_matched = matcher.number_of_matching_tokens(tokens[index:], debug)
                if rec_matched == 0:
                    return 0
                index += rec_matched
            else:
                raise ValueError(f"MatchGroup can only be used with Match, MatchGroup, and OptionalMatchGroup instances. Found {type(matcher)}")
        return index

class OptionalMatchGroup(MatchGroup):
    def __init__(self, *args: List[Union[Match, 'MatchGroup']], name = ""):
        super().__init__(*args, name=name)

    def number_of_matching_tokens(self, tokens: List[Token], debug=False) -> int:
        """
        Normal match group that only matches if all of the given Matching
        elements match tokens. However, a failure to match any token
        will not lead to a overall failure in the MatchGroup but instead
        skips ahead to the other group elements
        """
        if debug:
            if (self.name):
                print(f"Optional: {self.name}")
            else:
                print(f"Optional with {len(self.group_elements)} elements")

        return super().number_of_matching_tokens(tokens, debug)
    
class AnyOf(MatchGroup):
    def __init__(self, *args: List[Union[Match, 'MatchGroup', 'LazyMatchGroup']], name = ""):
        super().__init__(*args, name=name)
    
    def number_of_matching_tokens(self, tokens: List[Token], debug=False) -> int:
        """
        Returns the number of tokens this match group managed to match.
          0 = No matches for any of the given matching elements
        > 0 is returned for the first element in the given list of Match or MatchGroups
        that matches any tokens
        """
        if debug:
            if (self.name):
                print(f"Any of: {self.name}")
            else:
                print(f"Any of with {len(self.group_elements)} elements")

        if len(tokens) == 0:
            return 0

        for matcher in self.group_elements:
            if isinstance(matcher, LazyMatchGroup):
                matcher = matcher.infer_matching_group(debug)

            if isinstance(matcher, Match):
                if matcher.matches(tokens[0]):
                    if debug:
                        print(f"Matched token : {str(tokens[0])}")
                    return 1
            elif isinstance(matcher, MatchGroup):
                rec_matched = matcher.number_of_matching_tokens(tokens[0:], debug)
                if rec_matched > 0:
                    return rec_matched
            else:
                raise ValueError(f"AnyOf can only be used with Match and MatchGroup instances. Found {type(matcher)} {matcher}")
            
        return 0

class LazyMatchGroup():
    """
    A match group who's matching elements are generated lazy!
    -> This is needed for recursive definitions which would otherwise
       immediately lead to a stack overflow
    """

    def __init__(self, func: Callable[[], Union[Match, 'MatchGroup']], name=""):
        super().__init__()
        self.name = name
        self.func = func

    def infer_matching_group(self, debug):
        if debug:
            if (self.name):
                print(f"LazyMatchGroup: {self.name}")
            else:
                print(f"LazyMatchGroup with {len(self.group_elements)} elements")
        return self.func()

class Expression(MatchGroup):
    def __init__(self):
        self.elements = []
        self.left_expression = None
        self.right_expression = None
        self.math_expression = None
        self.total_result = None

        super().__init__(
            AnyOf(
                Decimal(lambda x: self.set_op(x)),
                SymbolIdentifier(None, lambda x: self.set_op(x)),
                LazyMatchGroup(
                    self.generate_left_recursive_expression,
                    name = f"Lazy left recursive Expression"
                ),
                name = "First expression identifier"
            ),
            OptionalMatchGroup(
                MathExpression(self.set_math),
                AnyOf(
                    Decimal(lambda x: self.set_op(x)),
                    SymbolIdentifier(None, lambda x: self.set_op(x)),
                    LazyMatchGroup(
                        self.generate_left_recursive_expression,
                        name = f"Lazy right recursive Expression"
                    ),
                    name = "Second expression identifier"
                ),
                name = "Math expression identifier"
            ),
            name="Expression"
        )

    def generate_left_recursive_expression(self):
        group, expression = self.generate_recursive_expression("left")
        self.left_expression = expression
        return group

    def generate_right_recursive_expression(self):
        group, expression = self.generate_recursive_expression("right")
        self.right_expression = expression
        return group

    def generate_recursive_expression(self, side: str):
        expression = Expression()
        group = MatchGroup(
            OptionalMatchGroup(
                Parentheses(True),
                name="Start ( Expression"
            ),
            expression,
            OptionalMatchGroup(
                Parentheses(False),
                name="End ) Expression"
            ),
            name = "Expression in parentheses"
        )
        return (group, expression)
    
    def number_of_matching_tokens(self, tokens: List[Token], debug=False) -> int:
        result = super().number_of_matching_tokens(tokens, debug)

        if result == 0:
            return result

        # We had a match of a expression -> Calculate all the properties!
        self.right_result = 0

        # Expression after any potential math symbol
        if self.right_expression != None:
            self.right_result = self.right_expression.evaluate()

        # Expression before any math symbol
        if self.left_expression != None:
            self.left_result = self.left_expression.evaluate()
            # If we have a left expression the right one can be the first constant!
            if len(self.elements) > 0:
                self.right_result = self.elements[0]
        else:
            self.left_result = self.elements[0]
            if len(self.elements) > 1:
                self.right_result = self.elements[1]

        # Calculate total result based on if there was a math expression
        if self.math_expression != None:
            self.total_result = self.math_expression(self.left_result, self.right_result)
        else:
            self.total_result = self.left_result

        return result
    
    def set_math(self, function: Callable[[int, int], int]):
        self.math_expression = function

    def set_op(self, element: Union[int, str]):
        if isinstance(element, str):
            self.elements.append(SymbolResolver.resolve_symbol(element))
        else:
            self.elements.append(element)

    def evaluate(self) -> int:
        """
        Evaluates the given expression to return an expression result!
        """
        return self.total_result

class Array(MatchGroup):
    def __init__(self):
        self.left_expression = Expression()
        self.right_expression = Expression()
        self.recursive_array = None
        super().__init__(
            ArrayParentheses(True),
            self.left_expression,
            OptionalMatchGroup(
                Dot(False),
                self.right_expression,
                name = "Array lower_limit_expression"
            ),
            ArrayParentheses(False),
            LazyMatchGroup(
                self.generate_recursive_array,
                name = "Lazy recursive Array"
            ),
            name = "Array"
        )
    
    def generate_recursive_array(self):
        self.recursive_array = Array()
        return OptionalMatchGroup(self.recursive_array)

    def number_of_matching_tokens(self, tokens: List[Token], debug=False) -> int:
        result = super().number_of_matching_tokens(tokens, debug)

        # Calculate all the properties!
        left = self.left_expression.evaluate()
        right = self.right_expression.evaluate()

        if left == None and right == None:
            self.lower_limit = 0
            self.upper_limit = 0
            self.size = 0
        else:
            # No right expression
            # Syntax, e.g. logic[N_STRM_AXI] test
            if right == None:
                self.lower_limit = 0
                self.upper_limit = left - 1
            else:
                self.lower_limit = min(left, right)
                self.upper_limit = max(left, right)
            
            self.size = (self.upper_limit - self.lower_limit) + 1 # + 1 because lower limit is inclusive

        if self.size > 0:
            self.dimensions = 1
            if self.recursive_array != None:
                self.dimensions += self.recursive_array.get_dimensions()
        else:
            self.dimensions = 0

        return result

    def get_lower_limit(self, dimension):
        """
        Gets the lower_limit (smallest possible index) for the dimension.
        Dimensions are 0-based
        """
        assert dimension < self.dimensions, f"Cannot access dimension index {dimension}. Array only has {self.dimensions}"
        if dimension == 0:
            return self.lower_limit
        else:
            return self.recursive_array.get_lower_limit(dimension - 1)
        
    def get_upper_limit(self, dimension):
        """
        Gets the upper_limit (largest possible index) for the dimension.
        Dimensions are 0-based
        """
        assert dimension < self.dimensions, f"Cannot access dimension index {dimension}. Array only has {self.dimensions}"
        if dimension == 0:
            return self.upper_limit
        else:
            return self.recursive_array.get_upper_limit(dimension - 1)

    def get_size(self, dimension):
        """
        Gets the size for the dimension.
        Dimensions are 0-based
        """
        assert dimension < self.dimensions, f"Cannot access dimension index {dimension}. Array only has {self.dimensions}"
        if dimension == 0:
            return self.size
        else:
            return self.recursive_array.get_size(dimension -1)
            
    def get_dimensions(self):
        return self.dimensions