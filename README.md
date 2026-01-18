# IOS Location Spoofer

https://github.com/user-attachments/assets/456d508c-2104-4d10-9458-e58e84b74788

## How it works

I did some research a few years back on how IOS location services worked: <https://github.com/acheong08/apple-corelocation-experiments>

TL;DR: iPhone scans for WIFI access points, sends the list of access points to Apple, Apple tells device where those points are, iPhone triangulates. What you can do here is have a VPN that does a Man in the Middle attack and rewrite the response with different values for where the access points are. The device then thinks that is where it is.

> MITM and processing are all done on device. No network connections are made by the app. It is safe to use...

## Building this yourself

- Go to `./GoSpoofer/` and run `make.sh`
- Open `./location-spoofer.xcodeproj/` with XCode
- Select a paid developer account (Required. PacketTunnel is a paid API)
- Run on iPhone?

## Usage

1. Open app
2. Go to "Location"
3. Enter a GPS coordinate or choose a preset
4. Go to VPN
5. Install profile
6. Connect to VPN
7. Go to Safari
8. Go to <http://mitm.it>
9. Download profile
10. Go to settings
11. Enable profile
12. Go to General > About > Certificate Trust Settings and enable Location Spoofer CA
13. Turn off and on location services
14. Go to maps and see it working

## Some annoying notes encountered along the way

- To do MITM on IOS, you need to do a weird song and dance. PacketTunnel -> Proxy -> Socks Server.
- See [HACKS.md](./HACKS.md). Apple won't let you upload if you have a `.a` in your bundle
- When you run out of memory in a service, you get SIGKILLED without notice or logs. I spent forever figuring out why I was randomly getting SIGKILLED. Answer is look at the Console app (wayyy to verbose)

## TODO

- I have already uploaded this onto TestFlight, but I highly doubt Apple would approve it. I will update when I get a response. It'd be cool if people could randomly just spoof their IOS location.
- Fix VPN bug

## Additional notes

This was partially vibe-coded, kinda, sorta. I wrote [apple-corelocation-experiments](https://github.com/acheong08/apple-corelocation-experiments) and [ios-mitm-demo](https://github.com/acheong08/ios-mitm-demo) by hand and told AI to combine them into 1. I'd say a solid 70% of code is reused and the AI didn't have to do any of the hard parts like reverse engineering. The objective was to test open source models (GLM-4.7 and MiniMax-M2.1) and how far they can go while also getting something useful out of it.

Results were mixed. AI can definitely do UI, but whenever it hit a real roadblock, it'll hullucinate, delete all tests, and try to cheat its way to success. For example, it failed to re-implement my ARPC parsing correctly, and instead of referencing the correct implementation and fixing its own, it tried to delete everything in Go and try to rewrite in Swift. A lot of times, I had to step in and fix whatever it was stuck on before proceeding.

IOS development is hell though and I can see how the lack of proper feedback for runtime issues can cause it to go crazy.

There are some **known bugs** even I can't figure out how to fix. For some reason, if you connect to another VPN, and try to connect to the location spoofer again, it will fail. You have to go to Settings > VPN and manually select the right profile before turning it on. Not enough references online for me to figure out. I am not an IOS developer and I do not have the time and energy to fix this. Workaround works well enough for my use case.
