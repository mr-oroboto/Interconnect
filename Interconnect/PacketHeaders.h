//
//  packet_headers.h
//  Interconnect
//
//  Created by oroboto on 17/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#ifndef PACKET_HEADERS_H
#define PACKET_HEADERS_H

#import <netinet/in.h>

/*****************************************************************************************************************
 * 802.3 ETHERNET HEADER
 *****************************************************************************************************************/

#define ETHER_HEADER_LEN 14
#define ETHER_ADDR_LEN	6

#define ETHER_TYPE_IP4  0x0800
#define ETHER_TYPE_ARP  0x0806
#define ETHER_TYPE_RARP 0x8035
#define ETHER_TYPE_VLAN 0x8100
#define ETHER_TYPE_IPV6 0x86DD

struct hdr_ethernet
{
    unsigned char   ether_dst[ETHER_ADDR_LEN];
    unsigned char   ether_src[ETHER_ADDR_LEN];
    unsigned short  ether_type;                             // IP, ARP etc
};

/*****************************************************************************************************************
 * IP HEADER
 *****************************************************************************************************************/

#define IP_HDR_LEN_WORDS(ip_hdr)	(((ip_hdr)->ip_vhl) & 0x0f)     // IP header length (32-bit words in header)
#define IP_HDR_LEN(ip_hdr)          (IP_HDR_LEN_WORDS(ip_hdr)*4)    // IP header length (bytes)
#define IP_VERSION(ip_hdr)          (((ip_hdr)->ip_vhl) >> 4)       // IP version

#define IP_FLAG_RF      0x8000		// reserved fragment flag
#define IP_FLAG_DF      0x4000		// don't fragment flag
#define IP_FLAG_MF      0x2000		// more fragments flag
#define IP_FLAG_OFFMASK 0x1fff      // mask for fragmenting bits

struct hdr_ip
{
    unsigned char   ip_vhl;             // version << 4 | header length >> 2
    unsigned char   ip_tos;
    unsigned short  ip_len;             // total length of this packet
    unsigned short  ip_id;
    unsigned short  ip_flags_offset;    // flags and fragment offset field, see IP_FLAG_ masks above
    unsigned char   ip_ttl;
    unsigned char   ip_proto;           // protocol
    unsigned short  ip_checksum;
    struct in_addr  ip_saddr;
    struct in_addr  ip_daddr;
};

/*****************************************************************************************************************
 * TCP HEADER
 *****************************************************************************************************************/
 
#define TCP_HDR_LEN_WORDS(tcp_hdr)	(((tcp_hdr)->tcp_offx2 & 0xf0) >> 4)    // TCP header length (32-bit words in header)
#define TCP_HDR_LEN(tcp_hdr)        (TCP_HDR_LEN_WORDS(tcp_hdr)*4)          // TCP header length (bytes)

#define TCP_FLAG_FIN 0x01
#define TCP_FLAG_SYN 0x02
#define TCP_FLAG_RST 0x04
#define TCP_FLAG_PUSH 0x08
#define TCP_FLAG_ACK 0x10
#define TCP_FLAG_URG 0x20
#define TCP_FLAG_ECE 0x40
#define TCP_FLAG_CWR 0x80
#define TCP_FLAGS (TCP_FLAG_FIN|TCP_FLAG_SYN|TCP_FLAG_RST|TCP_FLAG_ACK|TCP_FLAG_URG|TCP_FLAG_ECE|TCP_FLAG_CWR)

typedef unsigned int tcp_seq;

struct hdr_tcp
{
    unsigned short  tcp_sport;
    unsigned short  tcp_dport;
    tcp_seq         tcp_seq;
    tcp_seq         tcp_ack;
    unsigned char   tcp_offx2;      // data offset
    unsigned char   tcp_flags;
    unsigned short  tcp_window;
    unsigned short  tcp_checksum;
    unsigned short  tcp_urgent_ptr;
};

#endif /* PACKET_HEADERS_H */
