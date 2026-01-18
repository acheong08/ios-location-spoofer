# IOS Location Spoofer

https://github.com/user-attachments/assets/456d508c-2104-4d10-9458-e58e84b74788

## How it works

I did some research a few years back on how IOS location services worked: <https://github.com/acheong08/apple-corelocation-experiments>

TL;DR: iPhone scans for WIFI access points, sends the list of access points to Apple, Apple tells device where those points are, iPhone triangulates. What you can do here is have a VPN that does a Man in the Middle attack and rewrite the response with different values for where the access points are. The device then thinks that is where it is.

## Building this yourself

- Go to `./GoSpoofer/` and run `make.sh`
- Open `./location-spoofer.xcodeproj/` with XCode
- Select a paid developer account (Required. PacketTunnel is a paid API)
- Run on iPhone?

## Some annoying notes encountered along the way

- To do MITM on IOS, you need to do a weird song and dance. PacketTunnel -> Proxy -> Socks Server.
- See [HACKS.md](./HACKS.md). Apple won't let you upload if you have a `.a` in your bundle
- When you run out of memory in a service, you get SIGKILLED without notice or logs. I spent forever figuring out why I was randomly getting SIGKILLED. Answer is look at the Console app (wayyy to verbose)

## TODO

- I have already uploaded this onto TestFlight, but I highly doubt Apple would approve it. I will update when I get a response. It'd be cool if people could randomly just spoof their IOS location.
