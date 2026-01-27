class SymbolResolver():

    @staticmethod
    def resolve_symbol(symbol: str) -> int:
        # TODO: Read Coyote variables via CMAKE
        #       Ask users to specify other missing values?
        dict = {
            "FILTER_OPS_PER_STREAM": 3,
            "N_STRM_AXI": 6
        }

        return dict[symbol]