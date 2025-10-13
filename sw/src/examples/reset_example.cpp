#include <iostream>
#include <cstdlib>
#include "cThread.hpp"
#include "common.h"

int main() {
    try {
        // Get a cThread for the default vFPGA (ID 0)
        std::cout << "Creating cThread for vFPGA 0..." << std::endl;
        coyote::cThread cthread(0, getpid());
        
        // Perform hard reset using the helper function
        std::cout << "Performing hard reset..." << std::endl;
        common::hardResetUnit(&cthread, 0);
        
        std::cout << "Hard reset completed successfully!" << std::endl;
        
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
    
    return 0;
}
