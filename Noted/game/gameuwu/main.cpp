#include <iostream>
#include <thread>
#include <chrono>
#include <iomanip>

int main() {
    auto start = std::chrono::steady_clock::now();

    while (true) {
        auto now = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - start).count();

        int hours = elapsed / 3600;
        int minutes = (elapsed % 3600) / 60;
        int seconds = elapsed % 60;

        std::cout << "UwU : "
                  << std::setfill('0') << std::setw(2) << hours << "."
                  << std::setfill('0') << std::setw(2) << minutes << "."
                  << std::setfill('0') << std::setw(2) << seconds
                  << std::endl;

        std::this_thread::sleep_for(std::chrono::seconds(30));
    }

    return 0;
}