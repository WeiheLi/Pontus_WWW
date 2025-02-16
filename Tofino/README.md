# How to run P4 code in hardware
To run the experiment, please follow the steps below in the Tofino programmable switch.

## Set the sde environment
```bash
. bf-sde-9.7.0/tools/set_sde.bash 
```

## Compile the p4 implementation
```bash
sudo -E $SDE/tools/p4_build.sh pontus_1_ROW.p4
```

## Run bf_switchd
```bash
sudo -E $SDE/run_switchd.sh -p pontus_1_ROW
```

## Enable ports and fill the tables
```bash
sudo -E $SDE/run_bfshell.sh -b te_controller.py
```

## Run controller to get digests
```bash
python3 controller_digest.py [filename] [total number of entries] [total window size] [threshold rate]
```

