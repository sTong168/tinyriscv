Bridge FPGA-side protocol

Overview:
- This directory provides a simple FPGA-side bridge and memory models compatible with the chip-side `mem_bridge`.
- Target FPGA: xc7a35tfgg484-2 (user board). Pin assignment is user/board-specific.

Protocol (8-bit handshake):
- Chip -> FPGA: `ext_tx_o[7:0]` with `ext_tx_valid` asserted. FPGA must assert `ext_tx_ready` when it accepts the byte.
- FPGA -> Chip: `ext_rx_o[7:0]` with `ext_rx_valid` asserted. Chip must assert `ext_rx_ready` when it accepts the byte.

Command sequence (per transaction):
- CMD (1 byte): 0x01 = READ, 0x02 = WRITE
- ADDR (4 bytes): addr[31:24], addr[23:16], addr[15:8], addr[7:0]
- If WRITE: DATA (4 bytes) follow MSB first
- If READ: FPGA returns DATA (4 bytes) MSB first via `ext_rx` after receiving ADDR

Module mapping provided here for simulation/FPGA-side implementation:
- `bridge_fpga.v` : implements the protocol and simple memory access (parameterized depth)
- `rom_fpga.v`    : simple ROM model (default 256 x 32)
- `ram_fpga.v`    : simple RAM model (default 16 x 32)

Notes:
- The provided FPGA modules are simple models for simulation and initial FPGA integration. For real board use, replace `bridge_fpga` with a pin- and timing-accurate bridge that meets board constraints.
- ROM and RAM initial contents are zeros. You can initialize ROM using vendor tools or editing the `bridge_fpga` initial block.

