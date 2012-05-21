rubymotion-builder-tweaks
=========================

Tweaks to enhance the building and compiling of Ruby Motion files.



Change Log
----------
* Remove tweaked builder.rb as version 1.5 corrects all of these issues.
* Added rm_build.rake to handle tasks of copying XCode project resources into the motion app.
* Added support for compiling internationalized files in `resources/*.lproj`.
* Fix for properly compiling XCode `resources/*.xcdatamodeld` files in the in resources directory. Known bug likely to be fixed in next official release. 