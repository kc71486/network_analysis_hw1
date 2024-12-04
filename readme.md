# network_analysis_hw1
Homework. Only outputs result into file.
## result file format
Row: `beta=[20, 40, 60, 80, 100]`
Column: `discard_ratio storage_server_uptime_ratio`
## execute step

### build from source
#### requirement
```
zig >= 0.14.0-dev.1658+efc98fcbe
```
#### windows cmd
```batch
zig build -Doptimize=ReleaseSafe
move /Y zig-out\bin\network_sim.exe network_sim.exe
```
#### linux/macos
```bash
zig build -Doptimize=ReleaseSafe
mv -f zig-out/bin/network_sim.exe .
```
### download from github
Rename `network_sim-linux` or `network_sim-windows.exe` into `network_sim` or `network_sim.exe` respectively.
### run
#### windows cmd
```
network_sim.exe
```
#### linux/macos
```
network_sim
```