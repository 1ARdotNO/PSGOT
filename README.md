# PSGOT

This is an attempt to create a new package manager with multiple sources for installing and maintaining packages installed on windows.(maybe linux and mac alater)

The initial thesis is this,
One of the major hurdles of creating packages is getting the details, such as what command line switches to use, and what the download url's are etc.
Also detecting new versions is a hassle.
The intent is to bypass this by utilizing other open-source projects such as winget and chocolatey.
so to start this will serve as a new "front-end" for generating installation packages that can be deployed by many difrent means to workstations.

Planned installation providers;
-GPO
-Intune
-Standalone CLI client

Active installation providers:
-Intune