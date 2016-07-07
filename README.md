# Interconnect

Interconnect is a 3D visualisation tool for Mac OSX that monitors network traffic and displays the relationship between your machine and the hosts it is communicating with. Whilst primarily a novelty this can be useful for easily seeing communication with new, unexpected hosts (especially on unexpected port ranges) or simply understanding the total endpoints involved in serving a specific service such as a web page.

You can see a demo of Interconnect in action [here](http://www.vimeo.com).

## Prerequisites

You will need to install libpcap (which you can get courtesy of installing a tool such as [Wireshark](http://www.wireshark.org)) in order to use Interconnect. Additionally, the user with which you run Interconnect needs access to open **/dev/bfp\*** devices. If you install Wireshark you'll end up with an **access_bpf** group to which you can add your normal OSX user via the *"Users and Groups"* system preference tool.

## Features

### Interface and Capture Rule Selection

As expected, Interconnect is able to capture on a variety of locally connected interfaces and to filter out unwanted traffic using standard BPF capture rule syntax (the same syntax used by tcmpdump and described by the **pcap-filter** man page).

One caveat is that the capture interface must have an IP address configured.

### Configurable Host Groupings

Interconnect collects information on the hosts with which your machine communicates and attempts to capture data such as hostname, autonomous system (AS) number, hop count and round trip time (hop count information is only available if using one of the built-in traceroute style probing techniques).

In order to provide some context to communicating hosts they are grouped together using common metrics and clustered around a central point (the localhost). It is possible to group hosts based on:

- hop count from localhost (if using a traceroute probe)
- round-trip time to host
- host AS
- host network class

### Display of Intermediate Hops

Interconnect tries to only display hosts that are the ultimate endpoint of an IP packet sent to or from your machine. When using a traceroute probe it is possible to also display all intermediate hosts (routers) which packets to the host must traverse. Due to assymetric routing this option has the same caveats as a normal traceroute: packets are not guaranteed to always take this route nor are packets returning from that host guaranteed to take that route.
