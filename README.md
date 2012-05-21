rubymotion-builder-tweaks
=========================

Tweaks to enhance the building and compiling of Ruby Motion files.

builder.rb
----------
### Version 1.4
This file is located in your `/Library/RubyMotion/lib/motion/project` directory.



Change Log
----------
* Added support for compiling internationalized files in `resources/*.lproj`.
* Fix for properly compiling XCode `resources/*.xcdatamodeld` files in the in resources directory. Known bug likely to be fixed in next official release. 