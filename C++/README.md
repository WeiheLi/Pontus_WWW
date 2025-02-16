# Pontus

In today's data-intensive environments, real-time detection of persistent items—those consistently appearing over extended periods—is crucial for ensuring system correctness, reliability, and security. Persistent items can indicate critical issues like stealthy DDoS and botnet attacks. While various methods exist for analyzing persistent items, both frequent and infrequent, rapid data rates make recording every item for processing impractical. This paper introduces Pontus, a novel approach using an approximate data structure (sketch) designed for efficient and accurate detection of persistent items. Our method achieves fast, precise lookups and offers flexibility for addressing other types of persistent-based item detection with minor modifications. Extensive evaluations across diverse persistent-based tasks demonstrate Pontus's superior detection accuracy and processing speed compared to existing approaches.

## Pontus: Compilation and Execution Guide

This guide outlines the compilation and execution of Pontus examples on Ubuntu using g++ and make. Pontus, a C++ framework for data analysis and processing, comprises four main components: Persistence Estimation for gauging item persistence in data streams, Persistent Item Lookup for identifying high-persistence items, Significant Item Lookup for detecting items with both high persistence and frequency, and Persistent and Infrequent Item Lookup for finding items with high persistence but low frequency. Each component is contained in a separate folder within the repository, providing specialized functionality for different aspects of data stream analysis.

### Prerequisites
Ensure your system meets the following prerequisites:

- g++ (tested with version 9.4.0 on Ubuntu 20.04)

- make

- libpcap library (available via package managers like apt-get)

### Data Setup

- Download the required pcap file.

- Update the iptraces.txt file with the correct file path.

### Compilation Process
- To compile the examples, navigate to the respective folder and execute:

```
    $ make main_hitter
```
  

### Execution
- Run the compiled program using:

```
    $ ./main_hitter
```

- The program will output statistics on lookup accuracy, including F1 score, and other relevant metrics.
