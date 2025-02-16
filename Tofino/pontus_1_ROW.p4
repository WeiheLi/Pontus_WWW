/* -*- P4_16 -*- */

#include <core.p4>
#include <tna.p4>

#include "./include/types.p4"
#include "./include/headers.p4"
/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/
parser TofinoIngressParser(
        packet_in pkt,
        out ingress_intrinsic_metadata_t ig_intr_md) {
    state start {
        pkt.extract(ig_intr_md);
        transition select(ig_intr_md.resubmit_flag) {
            1 : parse_resubmit;
            0 : parse_port_metadata;
        }
    }
    state parse_resubmit {
        // Parse resubmitted packet here.
        transition reject;
    }
    state parse_port_metadata {
        pkt.advance(PORT_METADATA_SIZE);
        transition accept;
    }
}

parser IngressParser(packet_in        pkt,
    /* User */
    out my_ingress_headers_t          hdr,
    out my_ingress_metadata_t         meta,
    /* Intrinsic */
    out ingress_intrinsic_metadata_t  ig_intr_md)
{
    /* This is a mandatory state, required by Tofino Architecture */
    TofinoIngressParser() tofino_parser;

    state start {
        tofino_parser.apply(pkt, ig_intr_md);
        transition parse_ipv4;
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            TYPE_TCP:  parse_tcp;
            TYPE_UDP:  parse_udp;
            default: accept;
        }
    }

    state parse_tcp {
        pkt.extract(hdr.tcp);
        meta.proto = 6;
        meta.process_sketch = 1;
        transition select(hdr.tcp.is_recirc) {
            TYPE_RECIRC: parse_recirc;
            default: accept;
        }
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        meta.proto = 17;
        meta.process_sketch = 1;
        transition select(hdr.udp.is_recirc) {
            TYPE_RECIRC: parse_recirc;
            default: accept;
        }
    }

    state parse_recirc {
       pkt.extract(hdr.recirc);
       transition accept;
    }
}

/*************************************************************************
 **************  I N G R E S S   P R O C E S S I N G   *******************
 *************************************************************************/
/***************** M A T C H - A C T I O N  *********************/
control Ingress(
    /* User */
    inout my_ingress_headers_t                       hdr,
    inout my_ingress_metadata_t                      meta,
    /* Intrinsic */
    in    ingress_intrinsic_metadata_t               ig_intr_md,
    in    ingress_intrinsic_metadata_from_parser_t   ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t  ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t        ig_tm_md)
{
    action drop() {
        ig_dprsr_md.drop_ctl = 1;
    }

    /* Forward to a specific port */
    action ipv4_forward(PortId_t port) {
        ig_tm_md.ucast_egress_port = port;
    }
    /* Custom Do Nothing Action */
    action nop(){}

    /* REGISTERS */

    // ITEM KEY (K_ij)
    Register<bit<32>,bit<(INDEX_WIDTH)>>(MAX_REGISTER_ENTRIES) reg_item_src_ID;
    RegisterAction<bit<32>,bit<(INDEX_WIDTH)>,bit<32>>(reg_item_src_ID)
    read_update_item_src_ID = {
        void apply(inout bit<32> item_src_ID, out bit<32> output) {
            output = item_src_ID;
            if(item_src_ID == 0){
                item_src_ID = meta.current_item_src_ID;
            }
            else {
                if (meta.is_forced == 1){
                    item_src_ID = meta.current_item_src_ID;
                }
            }
        }
    };
    Register<bit<32>,bit<(INDEX_WIDTH)>>(MAX_REGISTER_ENTRIES) reg_item_dst_ID;
    RegisterAction<bit<32>,bit<(INDEX_WIDTH)>,bit<32>>(reg_item_dst_ID)
    read_update_item_dst_ID = {
        void apply(inout bit<32> item_dst_ID, out bit<32> output) {
            output = item_dst_ID;
            if(item_dst_ID == 0){
                item_dst_ID = meta.current_item_dst_ID;
            }
            else {
                if (meta.is_forced == 1){
                    item_dst_ID = meta.current_item_dst_ID;
                }
            }
        }
    };

    // PERSISTENCE VALUE (P_ij)
    Register<bit<16>,bit<(INDEX_WIDTH)>>(MAX_REGISTER_ENTRIES) reg_persistance_count;
    RegisterAction<bit<16>,bit<(INDEX_WIDTH)>,bit<16>>(reg_persistance_count)
    update_persistance_count = {
        void apply(inout bit<16> persistance_count, out bit<16> output) {
            if (meta.is_first == 1){
                persistance_count = 1;
            }
            else{
                persistance_count = persistance_count + meta.persistance_count_incr;
            }
            output = persistance_count;
        }
    };
    RegisterAction<bit<16>,bit<(INDEX_WIDTH)>,bit<16>>(reg_persistance_count)
    decay_persistance_count = {
        void apply(inout bit<16> persistance_count, out bit<16> output) {
            if (persistance_count != 1){
                persistance_count = persistance_count - 1;
            }
            else {
                persistance_count = 1;
            }
            output = persistance_count;
        }
    };
    RegisterAction<bit<16>,bit<(INDEX_WIDTH)>,bit<16>>(reg_persistance_count)
    read_only_persistance_count = {
        void apply(inout bit<16> persistance_count, out bit<16> output) {
            output = persistance_count;
        }
    };

    /* -- */

    // FLAGS
    //  F_ij = Flag to show if the tracked item arrived in the currents time window
    Register<bit<8>,bit<(INDEX_WIDTH)>>(MAX_REGISTER_ENTRIES) reg_F_ij;
    RegisterAction<bit<8>,bit<(INDEX_WIDTH)>,bit<8>>(reg_F_ij)
    read_update_F_ij = {
        void apply(inout bit<8> F_ij, out bit<8> output) {
            output = F_ij;
            F_ij = 1;
        }
    };
    //  R_ij = Flag to show if the persistence of the tracked item has been decreased due to hash conflicts with other items
    Register<bit<8>,bit<(INDEX_WIDTH)>>(MAX_REGISTER_ENTRIES) reg_R_ij;
    RegisterAction<bit<8>,bit<(INDEX_WIDTH)>,bit<8>>(reg_R_ij)
    read_update_R_ij = {
        void apply(inout bit<8> R_ij, out bit<8> output) {
            output = R_ij;
            R_ij = 1;
        }
    };
    RegisterAction<bit<8>,bit<(INDEX_WIDTH)>,bit<8>>(reg_R_ij)
    read_only_R_ij = {
        void apply(inout bit<8> R_ij, out bit<8> output) {
            output = R_ij;
        }
    };

    // OTHER REGISTERS
    /* Define Register for packet count */
    Register<bit<32>,bit<1>>(1) reg_pkt_count;
    RegisterAction<bit<32>,bit<1>,bit<32>>(reg_pkt_count)
    read_count_packet = {
        void apply(inout bit<32> pkt_count, out bit<32> output) {
            // if (pkt_count == 11146){ //caida2018 - Wind.Size: 2000
            // if (pkt_count == 22293){ //caida2018 - Wind.Size: 1000
            if (pkt_count == 14667){ //caida2018 - Wind.Size: 1500
                pkt_count = 0;
            }
            else {
                pkt_count = pkt_count + 1;
            }
            output = pkt_count;
        }
    };
    RegisterAction<bit<32>,bit<1>,bit<32>>(reg_pkt_count)
    read_only_count_packet = {
        void apply(inout bit<32> pkt_count, out bit<32> output) {
            output = pkt_count;
        }
    };

    /* Define Register for time window count */
    Register<bit<32>,bit<1>>(1) reg_time_window;
    RegisterAction<bit<32>,bit<1>,bit<32>>(reg_time_window)
    read_time_window = {
        void apply(inout bit<32> time_window, out bit<32> output) {
            time_window = time_window + 1;
        }
    };

    /* Define Register for recirculation count */
    Register<bit<32>,bit<1>>(1) reg_count_recirc;
    RegisterAction<bit<32>,bit<1>,bit<32>>(reg_count_recirc)
    read_count_recirc = {
        void apply(inout bit<32> count_recirc, out bit<32> output) {
            count_recirc = count_recirc + 1;
        }
    };

    /* ------------------------------------------------------------------------ */

    /* Declaration of the hashes*/
    Hash<bit<(INDEX_WIDTH)>>(HashAlgorithm_t.CRC16)   idx1_calc;
    // Hash<bit<(INDEX_WIDTH)>>(HashAlgorithm_t.CRC32)   idx1_calc;

    /* Calculate hash of the 5-tuple to represent the flow ID */
    action get_item_src_ID() {
        meta.current_item_src_ID = hdr.ipv4.src_addr;
    }
    action get_item_dst_ID() {
        meta.current_item_dst_ID = hdr.ipv4.dst_addr;
    }
    /* Calculate hash of the 2-tuple to use as 1st register index */
    action get_hash1() {
        meta.hash1 = idx1_calc.get({hdr.ipv4.src_addr, hdr.ipv4.dst_addr});
    }

    /* ------------------------------------------------------------------------ */

    /* Define 11b random number generator */
    Random<bit<11>>() random_gen;

    /* ------------------------------------------------------------------------ */

    /* Recirculate packet via loopback port 68 */
    action recirculate(bit<7> recirc_port) {
        ig_tm_md.ucast_egress_port[8:7] = ig_intr_md.ingress_port[8:7];
        ig_tm_md.ucast_egress_port[6:0] = recirc_port;
        hdr.recirc.setValid();
        hdr.recirc.persistance_count = meta.persistance_count;
        hdr.recirc.hash1 = (bit<16>)meta.hash1;
        hdr.recirc.is_recirc = 5;
    }

    action set_division_action(bit<16> f_action){
        meta.one_over_persistance = f_action;
    }
    action set_default_division_action(){
        meta.one_over_persistance = 1;
    }

    bit<16> diff_val1_val2_random;
    action diff_x_y_random(bit<16> f_value, bit<16> s_value){
        diff_val1_val2_random = (f_value - s_value);
    }

    /* ------------------------------------------------------------------------ */

    /* DIVISION TABLE */
    table division_table {
        key = {
            meta.divided_value: exact;
        }
        actions = {set_division_action; @defaultonly set_default_division_action;}
        size = 2100;
        const default_action = set_default_division_action();
    }

    /* ------------------------------------------------------------------------ */

    apply {
        get_item_src_ID();         // Get the item key (src)
        get_item_dst_ID();         // Get the item key (dst)
        get_hash1();               // Get the second hash value

        if (hdr.recirc.isValid()){ // RECIRCULATION
            read_count_recirc.execute(0); // Increase the recirc. count by one
            meta.is_forced = 1;
            if (hdr.recirc.persistance_count == 1){
                meta.R_ij = read_update_R_ij.execute((bit<(INDEX_WIDTH)>)hdr.recirc.hash1);
                meta.persistance_count = decay_persistance_count.execute((bit<(INDEX_WIDTH)>)hdr.recirc.hash1);
                meta.reg_item_src_ID  = read_update_item_src_ID.execute((bit<(INDEX_WIDTH)>)hdr.recirc.hash1); 
                meta.reg_item_dst_ID  = read_update_item_dst_ID.execute((bit<(INDEX_WIDTH)>)hdr.recirc.hash1);
                read_update_F_ij.execute((bit<(INDEX_WIDTH)>)hdr.recirc.hash1);
            }
            else {
                meta.R_ij = read_update_R_ij.execute((bit<(INDEX_WIDTH)>)hdr.recirc.hash1);
                meta.persistance_count = decay_persistance_count.execute((bit<(INDEX_WIDTH)>)hdr.recirc.hash1);
            }
            // Invalidate the recirculation header
            hdr.recirc.setInvalid();
            hdr.ethernet.ether_type = TYPE_IPV4;
            //
            ipv4_forward(292);

        }
        else {
            meta.is_forced = 0; 
            meta.pkt_count = read_count_packet.execute(0);
            if (meta.pkt_count == 0){
                read_time_window.execute(0);       // Increase current_time_window by one
                ig_dprsr_md.digest_type = 1;       // Activate the digest to setup the flags for each time window
            }
            /* FIRST HASH */
            if (meta.process_sketch == 1){
                meta.reg_item_src_ID  = read_update_item_src_ID.execute(meta.hash1);      // If it is NULL, it stores the current item directly in the register
                if (meta.reg_item_src_ID == 0){                                           // If the index is empty, store the current item and do not run the second hash 
                    meta.reg_item_dst_ID  = read_update_item_dst_ID.execute(meta.hash1);  // If it is NULL, it stores the current item directly in the register
                    if (meta.reg_item_dst_ID == 0){  // CASE 1: Empty bucket
                        meta.is_first = 1;
                        meta.persistance_count = update_persistance_count.execute(meta.hash1);   // It stores the persistance as 1
                        meta.F_ij = read_update_F_ij.execute(meta.hash1);             // It updates the F_ij flag as False (1)
                        meta.R_ij = read_update_R_ij.execute(meta.hash1);             // It updates the R_ij flag as False (1)
                    }
                }
                else if ((meta.reg_item_src_ID == meta.current_item_src_ID)) {            // Check if the key in the register entry is the same with the current item key
                    meta.reg_item_dst_ID  = read_update_item_dst_ID.execute(meta.hash1);
                    if ((meta.reg_item_dst_ID == meta.current_item_dst_ID)) { 
                        meta.is_first = 0;
                        meta.F_ij = read_update_F_ij.execute(meta.hash1);                 // Read the flag F_ij and set it as False if it is True
                        if (meta.F_ij == 0){  // CASE 2: Item already tracked in the bucket
                            meta.R_ij = read_update_R_ij.execute(meta.hash1);
                            if (meta.R_ij == 1){                                       // FALSE: Persistence has been decayed by another item       
                                meta.persistance_count_incr = 2;
                            }
                            else {                                                     // TRUE: No reduction by another item
                                meta.persistance_count_incr = 1;
                            }
                            meta.persistance_count = update_persistance_count.execute(meta.hash1); 
                        }  
                        else {
                            meta.persistance_count = read_only_persistance_count.execute(meta.hash1);
                            meta.R_ij = read_only_R_ij.execute(meta.hash1);
                            meta.prob_replacement = 1;
                        }
                    }
                    else{
                        meta.persistance_count = read_only_persistance_count.execute(meta.hash1);
                        meta.R_ij = read_only_R_ij.execute(meta.hash1);
                        meta.prob_replacement = 1;
                    }
                }
                else{
                    meta.persistance_count = read_only_persistance_count.execute(meta.hash1);
                    meta.R_ij = read_only_R_ij.execute(meta.hash1);
                    meta.prob_replacement = 1;
                }
                 
                // CASE 3: PROBABILISTIC REPLACEMENT  
                meta.random_value = (bit<16>)random_gen.get();
                if (meta.prob_replacement == 1){
                    meta.divided_value = meta.persistance_count + 1;  // Get the result of (2^11)/(persistence_count + 1)
                    division_table.apply();
                    diff_x_y_random(meta.one_over_persistance, meta.random_value);
                    if (diff_val1_val2_random[15:15] == 0) {    // Rand(0, 2^11) < ((2^11)/(persistence_count + 1))
                        if (meta.R_ij == 0){
                            recirculate(68);
                            if (meta.proto == 6){ 
                                hdr.tcp.is_recirc = TYPE_RECIRC;
                            }
                            if (meta.proto  == 17){
                                hdr.udp.is_recirc = TYPE_RECIRC;
                            }
                        }
                    }
                }
            }
        }

    } //END OF APPLY

} //END OF INGRESS CONTROL

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control IngressDeparser(packet_out pkt,
    /* User */
    inout my_ingress_headers_t                       hdr,
    in    my_ingress_metadata_t                      meta,
    /* Intrinsic */
    in    ingress_intrinsic_metadata_for_deparser_t  ig_dprsr_md)
{
    // Checksum() ipv4_checksum;
    Digest<flow_class_digest>() digest;
    apply {
        /* we do not update checksum because we used ttl field for stats*/

        if (ig_dprsr_md.digest_type == 1) {

            digest.pack({hdr.ipv4.src_addr, hdr.ipv4.dst_addr, meta.pkt_count});
        }
        pkt.emit(hdr.ipv4);
        pkt.emit(hdr.tcp);
        pkt.emit(hdr.udp);
        pkt.emit(hdr.recirc);
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/
#include "./include/egress.p4"

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/
Pipeline(
    IngressParser(),
    Ingress(),
    IngressDeparser(),
    EgressParser(),
    Egress(),
    EgressDeparser()
) pipe;

Switch(pipe) main;
