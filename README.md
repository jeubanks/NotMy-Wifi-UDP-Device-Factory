# NotMy-Wifi-UDP-Switch-Controller
Original V1.9 of cybrmage's WiFi UDP Switch Controller
Current version 2.0 with changes by JimMcGhee.

PREAMBLE
Most importantly, this is not my original work.  It was originally written by CYBRMAGE and at least partially derived from the Wemo plugin by FUTZLE.
The original version was written by CYBRMAGE and called 'ECO SWITCH' V1.0 and was renamed by CYBRMAGE to 'WiFi UDP Switch Controller V1.9.
Unfortunately, this version does not initialize on my Vera Plus.  Thus, my changes.

FUNCTION
This plugin is used to control ECO Switch, TPLINK Switch, TPLINK LB100(US) and LB120(US) bulbs and SENGLED Boost bulb/WiFi repeater.

GET THE UPDATED FILES
Click the green 'Clone or Download' button and then the 'Download ZIP'.
Extract the files just downloaded to prepare for the installation.

INSTALLATION
1. Use the native phone app (ECO Plug, Kasa, or Boost) to install the device.
2. Goto Apps/Install Apps and search for wifi udp.  When found, click 'details' and install it.
3. Allow Vera to install the app and reboot its self.  ECO Switch will fail to initialize.  This is to be expected.
4. Go to apps/develop apps and click on luup files.
5. Grap all the files in the directory you unziped eariler except the LICIENCE AND README and drop them on the green 'Upload' button.
6. Wait for the Vera to reboot and then reload your browser.

SET UP DISCOVERED DEVICES
