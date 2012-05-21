rubymotion-builder-tweaks
=========================

Tweaks to enhance the building and compiling of Ruby Motion files.

builder.rb
----------
### Version 1.5
This corrects a missing set of parentheses on line 290.

This file is located in your `/Library/RubyMotion/lib/motion/project` directory.



Change Log
----------
* Added back builder.rb as the 1.5 release version has a typo in the section for building nibs.
* Moved rake file into tasks subdirectory
* Remove tweaked builder.rb as version 1.5 corrects all of these issues.
* Added rm_build.rake to handle tasks of copying XCode project resources into the motion app.
* Added support for compiling internationalized files in `resources/*.lproj`.
* Fix for properly compiling XCode `resources/*.xcdatamodeld` files in the in resources directory. Known bug likely to be fixed in next official release. 