# rubymotion-builder-tweaks
===========================
Tweaks to enhance the building and compiling of Ruby Motion files.
- - -
### builder.rb
**For RubyMotion 1.5**  
This corrects a missing set of parentheses on line 290 of the file located in `/Library/RubyMotion/lib/motion/project`.
- - -
### tasks/rm_build.rake

This file includes a variety of methods to deal with managing XCode resources in a RubyMotion project. Add the `/tasks` directory to your project and include the file at the top of your Rakefile. By default, the XCode project resources are expected to be in an `/xcode/projectname` directory of your project.  This can be changed by modifying the `XCODE_PROJECT_PATH` of the `/tasks/rm_build.rake` file.

#### Installation
```ruby
  # RubyMotionProject/Rakefile
  $:.unshift("/Library/RubyMotion/lib")
  require 'motion/project'
  
  # add this line
  import 'tasks/rm_build.rake'
  
```

#### Rake Usage
| nibs |  | 
|:--------------------|---------------------------------------------------------------------------------|
| `rake nibs:clean`   | Remove all \*.nib, \*.xib, \*.lproj files from the project's `/resources` directory |
| `rake nibs:copy`    | Copy all \*.nib, \*.xib, \*.lproj files from the XCode project to `/resources`      |
| `rake nibs:update`  | Performs a `clean` and `copy` of all nibs files                                      |
| `rake nibs` 		  | Convenience alias for `rake nibs:update`                                         |
| **data** |  | 
| `rake data:clean`   | Remove all \*.xcdatamodeld, \*.momd files from the project's `/resources` directory |
| `rake data:copy`    | Copy all \*.xcdatamodeld files from the XCode project to `/resources`      |
| `rake data:update`  | Performs a `clean` and `copy` of all data files                                      |
| `rake data` 		  | Convenience alias for `rake data:update`                                         |
| **Miscellaneous**&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; |  |
| `rake rebuild` | Cleans the project by removing `/build` directory and performing `nibs:update`, `data:update`,  and building the project for the simulator.


- - -
#### Change Log
* Improved README.md
* Added back builder.rb as the 1.5 release version has a typo in the section for building nibs.
* Moved rake file into tasks subdirectory
* Remove tweaked builder.rb as version 1.5 corrects all of these issues.
* Added rm_build.rake to handle tasks of copying XCode project resources into the motion app.
* Added support for compiling internationalized files in `resources/*.lproj`.
* Fix for properly compiling XCode `resources/*.xcdatamodeld` files in the in resources directory. Known bug likely to be fixed in next official release. 