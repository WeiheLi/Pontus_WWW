# Pontus

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.14876754.svg)](https://doi.org/10.5281/zenodo.14876754)

In modern data-intensive environments, real-time detection of persistent items—those consistently appearing over time—is essential for ensuring system reliability, security, and correctness. Persistent items can signal critical threats such as stealthy DDoS or botnet attacks. However, analyzing both frequent and infrequent persistent items at high data rates is challenging, as storing every item for processing is impractical.  

We introduce **Pontus**, a novel approach leveraging an approximate data structure (sketch) for efficient and accurate persistent item detection. Our method enables fast, precise lookups and can be easily adapted for other persistence-based detection tasks with minor modifications. This repository presents the **C++ and Tofino implementation** of our approach.
