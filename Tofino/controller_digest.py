#!/usr/bin/python3

from __future__ import print_function

import os
import sys
import pdb

SDE_INSTALL   = os.environ['SDE_INSTALL']
SDE_PYTHON2   = os.path.join(SDE_INSTALL, 'lib', 'python2.7', 'site-packages')
sys.path.append(SDE_PYTHON2)
sys.path.append(os.path.join(SDE_PYTHON2, 'tofino'))

PYTHON3_VER   = '{}.{}'.format(
                    sys.version_info.major,
                    sys.version_info.minor)
SDE_PYTHON3   = os.path.join(SDE_INSTALL, 'lib', 'python' + PYTHON3_VER, 'site-packages')
sys.path.append(SDE_PYTHON3)
sys.path.append(os.path.join(SDE_PYTHON3, 'tofino'))
sys.path.append(os.path.join(SDE_PYTHON3, 'tofino', 'bfrt_grpc'))

import grpc
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as bfrt_client
import pandas as pd

import time
import socket, struct

filename_out = sys.argv[1]
register_size = int(sys.argv[2]) # Adjust to match the size of the register.
window_size = int(sys.argv[3])   # Total number of window size
rate = float(sys.argv[4])        # Rate
print('Number of entries: ', register_size, ' Window size: ', window_size, ' Rate: ', rate)
# register_size = 16384
# window_size = 1000
# rate = 0.5

# Connect to the BF Runtime Server
#
interface = bfrt_client.ClientInterface(
    grpc_addr = 'localhost:50052',
    client_id = 1,
    device_id = 0)
print('Connected to BF Runtime Server')

#
# Get the information about the running program
#
bfrt_info = interface.bfrt_info_get()
print('The target runs the program ', bfrt_info.p4_name_get())
#
# Establish that you are using this program on the given connection
#
interface.bind_pipeline_config(bfrt_info.p4_name_get())
learn_filter = bfrt_info.learn_get("digest")

# List of registers
registers = ['Ingress.reg_F_ij','Ingress.reg_R_ij']

# Target pipe_id=0xffff
target = bfrt_client.Target(device_id=0, pipe_id=0xffff)

flow_counter = 0
count_digest = 0
count_refresh = 0
result_df = pd.DataFrame()

while True:

    try:
        digest = interface.digest_get(timeout=50)
        recv_target = digest.target
        digest_type = 1
        data_list = learn_filter.make_data_list(digest)
    except:
        digest_type = 0
        persistance_list = []
        src_id_list = []
        dst_id_list = []
        
        table_persistance = bfrt_info.table_get('Ingress.reg_persistance_count')
        table_item_src_ID = bfrt_info.table_get('Ingress.reg_item_src_ID')
        table_item_dst_ID = bfrt_info.table_get('Ingress.reg_item_dst_ID')
        table_time = bfrt_info.table_get('Ingress.reg_time_window')
        table_recirc = bfrt_info.table_get('Ingress.reg_count_recirc')
        resp_persistance = table_persistance.entry_get(bfrt_client.Target(device_id=0, pipe_id=0xffff), required_data=None,
                                key_list=None, flags={"from_hw":True}, p4_name=bfrt_info.p4_name_get())
        
        resp_item_src_ID = table_item_src_ID.entry_get(bfrt_client.Target(device_id=0, pipe_id=0xffff), required_data=None,
                                key_list=None, flags={"from_hw":True}, p4_name=bfrt_info.p4_name_get())
        
        resp_item_dst_ID = table_item_dst_ID.entry_get(bfrt_client.Target(device_id=0, pipe_id=0xffff), required_data=None,
                                key_list=None, flags={"from_hw":True}, p4_name=bfrt_info.p4_name_get())
        
        resp_time = table_time.entry_get(bfrt_client.Target(device_id=0, pipe_id=0xffff), required_data=None,
                                key_list=None, flags={"from_hw":True}, p4_name=bfrt_info.p4_name_get())
        
        resp_recirc = table_recirc.entry_get(bfrt_client.Target(device_id=0, pipe_id=0xffff), required_data=None,
                                key_list=None, flags={"from_hw":True}, p4_name=bfrt_info.p4_name_get())
                    
        
        for data, x in resp_persistance:
            x_dict = x.to_dict()
            data_dict = data.to_dict()
            persistance_list.append(data_dict['Ingress.reg_persistance_count.f1'][2])
            
        for data, x in resp_item_src_ID:
            x_dict = x.to_dict()
            data_dict = data.to_dict()
            src_id_list.append(data_dict['Ingress.reg_item_src_ID.f1'][2])
        
        for data, x in resp_item_dst_ID:
            x_dict = x.to_dict()
            data_dict = data.to_dict()
            dst_id_list.append(data_dict['Ingress.reg_item_dst_ID.f1'][2])
        
        result_df['Persistance'] = persistance_list
        result_df['src_ID'] = src_id_list
        result_df['dst_ID'] = dst_id_list
        
        thr = window_size*rate
        print('PERSISTENCE COUNT: ', len(result_df[result_df['Persistance'] >= thr]))
        # print('WINDOW: ', count_refresh)
        
        for data, x in resp_time:
            x_dict = x.to_dict()
            data_dict = data.to_dict()
            print('TIME WINDOW: ', data_dict['Ingress.reg_time_window.f1'][2])
            
        for data, x in resp_recirc:
            x_dict = x.to_dict()
            data_dict = data.to_dict()
            print('RECIRC COUNT: ', data_dict['Ingress.reg_count_recirc.f1'][2])
            
        break
    

    if digest_type == 1:

        flow_counter = flow_counter + len(data_list)

        keys_reg = {'Ingress.reg_F_ij': [],'Ingress.reg_R_ij': []}
        datas_reg = {'Ingress.reg_F_ij': [],'Ingress.reg_R_ij': []}

        for dd in data_list:
            count_digest = count_digest + 1
            data_dict = dd.to_dict()
            # convert ip address into normal format
            source_addr = socket.inet_ntoa(struct.pack('!L', data_dict['source_addr']))
            destin_addr = socket.inet_ntoa(struct.pack('!L', data_dict['destin_addr']))
            pkt_count = data_dict['pkt_count']
            ###########
            if (count_digest%150 == 6):
                persistance_list = []
                table = bfrt_info.table_get('Ingress.reg_persistance_count')
                resp = table.entry_get(bfrt_client.Target(device_id=0, pipe_id=0xffff), required_data=None,
                                        key_list=None, flags={"from_hw":True}, p4_name=bfrt_info.p4_name_get())
                
                for data, x in resp:
                    x_dict = x.to_dict()
                    data_dict = data.to_dict()
                    persistance_list.append(data_dict['Ingress.reg_persistance_count.f1'][2])
                # print(persistance_list)
                
                count_thr = 0
                for p in persistance_list:
                    if p >= rate*count_refresh:
                        count_thr = count_thr + 1
                print('PERSISTENT ITEM COUNT: ' ,count_thr)
                print('WINDOW: ', count_refresh + 1)
                print('--**--')
                        
            if (pkt_count == 0):
                count_refresh = count_refresh + 1
                for reg_name in registers:
                    reg_tbl = bfrt_info.table_get(reg_name)
                    # reg_tbl.clear()
                    for register_index in range(register_size):
                        keys_reg[reg_name].append(reg_tbl.make_key([bfrt_client.KeyTuple('$REGISTER_INDEX', register_index)]))
                        datas_reg[reg_name].append(reg_tbl.make_data([bfrt_client.DataTuple(reg_name+'.f1', 0)]))
                    


            for reg_name in registers:
                reg_tbl = bfrt_info.table_get(reg_name)
                reg_tbl.entry_mod(target, key_list=keys_reg[reg_name], data_list=datas_reg[reg_name], flags={"from_hw":True}, p4_name=bfrt_info.p4_name_get())
            

result_df.to_csv(filename_out)    