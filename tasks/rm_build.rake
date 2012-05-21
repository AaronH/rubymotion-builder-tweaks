#
# Tasks to assist in building and compiling Ruby Motion projects
# https://github.com/AaronH/rubymotion-builder-tweaks
#

##
## Include this file at the top of your RubyMotion project's Rakefile.
##    include 'tasks/rm_build.rake'


## Point this to the location of your xcode project files.
## In this case, the files are in a subdirectory of the RubyMotion app.
## i.e. RUBYMOTOION_PROJECT_ROOT/xcode/PROJECT_NAME/
##
## Path can be relative or absolute.
XCODE_PROJECT_PATH  = %(xcode/**/)
RESOURCES_PATH      = %(./resources/)

##### NIBS
## Tasks for dealing with .xib and internationalization files
##
namespace :nibs do

  desc "Remove old .nib, .xib, and .lproj files from resources directory"
  task :clean do
    clean_resource_files %w(*.xib *.nib *.lproj)
  end

  desc "Copy the .xib and .lproj files from selected XCode directory"
  task :copy do
    copy_resource_files %w(*.xib *.lproj)
  end

  desc "Update all nibs and localization files"
  task update: [:clean, :copy]

end

##### DATA
## Tasks for dealing with .xib and internationalization files
##
namespace :data do

  desc "Remove old data models files from resources directory"
  task :clean do
    clean_resource_files %w(*.xcdatamodeld *.momd)
  end

  desc "Copy the .xcdatamodeld files from selected XCode directory"
  task :copy do
    copy_resource_files  %w(*.xcdatamodeld)
  end

  desc "Update all nibs and localization files"
  task update: [:clean, :copy]

end


##### CONVENIENCE
## Convience shortcuts to handle common tasks
##
desc "Clean project, update all XCode files in resources directory and rebuild for simulator."
task rebuild: ['nibs:update', 'data:update', :clean, 'build:simulator', :simulator]

desc "Update all .xib and .lproj files in resources directory and    for simulator"
task nibs: ['nibs:update', 'build:simulator', :simulator]

desc "Shortcut to rebuild data files"
desc "Update all .xcdatamodeld files in resources directory and rebuild for simulator"
task data: ['data:update', 'build:simulator', :simulator]



##### Helpers
## Helper methods
##
def xcode_path_for(file)
  # return the path for required files
  %(#{XCODE_PROJECT_PATH}#{file})
end

def resource_path_for(file)
  # path to project's resource files
  %(#{RESOURCES_PATH}#{file})
end

def clean_resource_files(*files)
  # remove file from resources directory
  if (files = [*files].flatten).any?
    puts "Removing #{files.join ', '} from #{RESOURCES_PATH}..."
    files.each do |file|
      %x{rm -rf #{resource_path_for file}} #rescue nil
    end
  end
end

def copy_resource_files(*files)
  # copy file from XCode project to resources directory
  if (files = [*files].flatten).any?
    puts "Copying #{files.join ', '} to #{RESOURCES_PATH}..."
    files.each do |file|
      %x{cp -rf #{xcode_path_for file} #{RESOURCES_PATH}}
    end
  end
end
