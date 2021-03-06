#include "distributed_stateful_load_balancer_sync_header.p4"
#include "distributed_stateful_load_balancer_s1_sync.p4"
#include <core.p4>
#include <v1model.p4>

struct meta_t {
    bit<32> temp;
    bit<16> hash;
    bit<32> routing_port;
    bit<32> probe_bool;
    bit<32> upper_limit;
    bit<32> lower_limit;
}

header load_balancer_t {
    bit<64> preamble;
    bit<32> syn;
    bit<32> fin;
    bit<32> fid;
    bit<32> subfid;
    bit<32> packet_id;
    bit<32> hash;
    bit<32> _count;
}

struct metadata {
    @name(".meta") 
    meta_t meta;
}

struct headers {
    @name(".load_balancer_head") 
    load_balancer_t load_balancer_head;
}

parser ParserImpl(packet_in packet, out headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    @name(".parse_head") state parse_head {
        packet.extract(hdr.load_balancer_head);
        transition accept;
    }
    @name(".parse_head_and_sync") state parse_head_and_sync {
        packet.extract(hdr.load_balancer_head);
        transition accept;
    }
    @name(".start") state start {
        transition select((packet.lookahead<bit<64>>())[63:0]) {
            64w0: parse_head;
            64w1: parse_head;
            64w2: parse_head_and_sync;
            default: accept;
        }
    }
}

control egress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    apply {
    }
}

@name(".flow_to_port_map_register") register<bit<32>, bit<16>>(32w65536) flow_to_port_map_register;

@name(".total_flow_count_register") register<bit<32>, bit<4>>(32w14) total_flow_count_register;

control ingress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    @name(".clear_map") action clear_map() {
        hash(meta.meta.hash, HashAlgorithm.crc16, (bit<16>)0, { hdr.load_balancer_head.fid }, (bit<32>)65536);
        flow_to_port_map_register.write((bit<16>)meta.meta.hash, (bit<32>)0);
    }
    @name(".forward") action forward() {
        hash(meta.meta.hash, HashAlgorithm.crc16, (bit<16>)0, { hdr.load_balancer_head.fid }, (bit<32>)65536);
        flow_to_port_map_register.read(meta.meta.routing_port, (bit<16>)meta.meta.hash);
        standard_metadata.egress_spec = (bit<9>)meta.meta.routing_port;
    }
    @name("._drop") action _drop() {
        mark_to_drop(standard_metadata);
    }
    @name(".get_limits") action get_limits(bit<32> upper_limit, bit<32> lower_limit) {
        meta.meta.upper_limit = upper_limit;
        meta.meta.lower_limit = lower_limit;
    }
    @name(".get_server_flow_count") action get_server_flow_count() {
    }
    @name(".update_flow_count") action update_flow_count() {
        total_flow_count_register.read(meta.meta.temp, (bit<4>)(bit<4>)(meta.meta.routing_port - 32w2));
        meta.meta.temp = meta.meta.temp - 32w1;
        total_flow_count_register.write((bit<4>)(bit<4>)(meta.meta.routing_port - 32w2), (bit<32>)meta.meta.temp);
    }
    @name(".update_map") action update_map() {
        hash(meta.meta.hash, HashAlgorithm.crc16, (bit<16>)0, { hdr.load_balancer_head.fid }, (bit<32>)65536);
        flow_to_port_map_register.write((bit<16>)meta.meta.hash, (bit<32>)standard_metadata.egress_spec);
    }
    @name(".update_switch_flow_count") action update_switch_flow_count() {
    }
    @name(".clear_map_table") table clear_map_table {
        actions = {
            clear_map;
        }
        size = 1;
    }
    @name(".forwarding_table") table forwarding_table {
        actions = {
            forward;
            _drop;
        }
        key = {
	    meta.meta.routing_port: exact;
        }
        size = 1;
    }
    @name(".get_limits_table") table get_limits_table {
        actions = {
            get_limits;
        }
        size = 1;
    }
    @name(".get_server_flow_count_table") table get_server_flow_count_table {
        actions = {
            get_server_flow_count;
        }
        size = 1;
    }
    @name(".update_flow_count_table") table update_flow_count_table {
        actions = {
            update_flow_count;
        }
        size = 1;
    }
    @name(".update_map_table") table update_map_table {
        actions = {
            update_map;
        }
        size = 1;
    }
    @name(".update_switch_flow_count_table") table update_switch_flow_count_table {
        actions = {
            update_switch_flow_count;
        }
        size = 1;
    }
    apply {
        get_limits_table.apply();
        get_server_flow_count_table.apply();
        if (hdr.load_balancer_head.preamble == 64w1) {
        } else {
            if (hdr.load_balancer_head.preamble == 64w2) {
                update_switch_flow_count_table.apply();
            } else {
                if (hdr.load_balancer_head.syn == 32w1) {
                    update_map_table.apply();
                }
                forwarding_table.apply();
                if (meta.meta.probe_bool == 32w1) {
                }
                if (hdr.load_balancer_head.fin == 32w1) {
                    clear_map_table.apply();
                    update_flow_count_table.apply();
                }
            }
        }
    }
}

control DeparserImpl(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.load_balancer_head);
    }
}

control verifyChecksum(inout headers hdr, inout metadata meta) {
    apply {
    }
}

control computeChecksum(inout headers hdr, inout metadata meta) {
    apply {
    }
}

V1Switch(ParserImpl(), verifyChecksum(), ingress(), egress(), computeChecksum(), DeparserImpl()) main;

