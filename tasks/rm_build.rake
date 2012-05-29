FileUtils rescue require('FileUtils')
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
XCODE_PROJECT_PATH  = %(xcode/**)
RESOURCES_PATH      = %(./resources/)

# this is a map of the base XCode extensions and their
# compiled counterparts
RESOURCE_FILES_MAP  = {          xib: :nib,
                          storyboard: :storyboardc,
                               lproj: nil,
                             strings: nil,
                        xcdatamodeld: :momd }

##### RESOURCES
## Tasks for dealing with resource files
##
namespace :resources do
  # Automatically update any resource files that need it.
  task :update do
    update_resource_files
  end

  task clean: ['nibs:clean', 'data:clean']

  # Automatically update any resource files that need it.
  task force: :clean do
    update_resource_files force: true
  end
end

##### NIBS
## Tasks for dealing with .xib and internationalization files
##
namespace :nibs do

  desc "Remove old .nib, .xib, .lproj, and .storyboard files from resources directory"
  task :clean do
    clean_resource_files %w(*.xib *.nib *.lproj *.storyboard *.storyboardc)
  end

  desc "Copy the .xib and .lproj files from selected XCode directory"
  task :copy do
    copy_resource_files %w(*.xib *.lproj *.storyboard)
  end

  desc "Update the nib based files in the project"
  task :update do
    update_resource_files extensions: (RESOURCE_FILES_MAP.keys - [:xcdatamodeld])
  end

  desc "Force update of all nibs, storyboards, and localization files"
  task force: [:clean, :copy]
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

  desc "Update the nib based files in the project"
  task :update do
    update_resource_files extensions: :xcdatamodeld
  end

  desc "Update all nibs and localization files"
  task force: [:clean, :copy]

end


##### CONVENIENCE
## Convience shortcuts to handle common tasks
##
desc "Clean project, update all XCode files in resources directory and rebuild for simulator."
task rebuild: ['resources:force', :clean, 'build:simulator', :simulator]

desc "Automatically update any resource files in your project and build for simulator"
task resources: ['resources:update', 'build:simulator', :simulator]
task b: :resources

desc "Update all .xib and .lproj files in resources directory and for simulator"
task nibs: ['nibs:update', 'build:simulator', :simulator]

desc "Shortcut to rebuild data files"
desc "Update all .xcdatamodeld files in resources directory and rebuild for simulator"
task data: ['data:update', 'build:simulator', :simulator]



##### Helpers
## Helper methods
##
def update_resource_files(options = {})
  if Dir[XCODE_PROJECT_PATH].any?
    App.info 'Updating', "Resource files..."
    unless Dir.exists?(RESOURCES_PATH)
      FileUtils.mkdir_p RESOURCES_PATH
    end
    xcode_resources(XCODE_PROJECT_PATH, options).each do |file|
      if options[:force] or resource_needs_updating?(file)
        # make sure we delete any compiled version first...
        delete_compiled_resource_for file
        # then copy the source
        copy_source_resource file
      end
    end
    puts "\n"
  else
    App.info '! Warning !', "I couldn't find an XCode project directory :: #{XCODE_PROJECT_PATH}\n"
  end
end

def xcode_path_for(file)
  # return the path for required files
  File.join XCODE_PROJECT_PATH, file
end

def resource_path_for(file)
  # path to project's resource files
  File.join RESOURCES_PATH, file
end

def clean_resource_files(*files)
  # remove file from resources directory
  if (files = [*files].flatten).any?
    App.info 'Removing', "#{files.join ', '} from #{RESOURCES_PATH}"
    files.each do |file|
      %x{rm -rf #{resource_path_for file}} #rescue nil
    end
  end
end

def copy_resource_files(*files)
  # copy file from XCode project to resources directory
  if (files = [*files].flatten).any?
    App.info 'Copying', "#{files.join ', '} to #{RESOURCES_PATH}"
    files.each do |file|
      %x{cp -rf #{xcode_path_for file} #{RESOURCES_PATH}}
    end
  end
end

# get an array of all possible resource files in the XCode path
def xcode_resources(directory = XCODE_PROJECT_PATH, options = {})
  extensions = [*(options[:extensions] || RESOURCE_FILES_MAP.keys)].flatten.map{|e| %(*.#{e})}
  extensions += [*options[:files]] if options[:files]
  directories = extensions.flatten.compact.uniq.map{|e| File.join directory, e}
  Dir[*directories].map do |dir|
    if File.directory?(dir)
      find_options = {}
      find_options[:files] = %w(* .xccurrentversion) if dir =~ /xcdatamodel/
       xcode_resources dir, find_options
    else
      dir
    end

  end.flatten.compact.uniq
end

# Determine where the source item should live in the project directory.
# Feels a little hacky to test for lproj directly. Should probably come
# up with a better way to deal with subdirectories in case of future
# RubyMotion updates
def project_resource(path)
  path = if match = path.match(/\/(([^\.\/]+\.(lproj|xcdatamodeld?)).+)/)
            match[1]
          end || File.basename(path)
  resource_path_for path
end

# The filename for the compiled version of a source file
def compiled_file_from_source(file)
  extension = File.extname(file).gsub(/^\./,'')
  if compiled = RESOURCE_FILES_MAP[extension.to_sym]
    file.gsub Regexp.new(%(#{extension}$)), compiled.to_s
  end
end

# The full path name for a compiled resource
def compiled_resource_for(file)
  if file = compiled_file_from_source(file)
    project_resource file
  end
end

def delete_compiled_resource_for(file)
  file = compiled_resource_for file
  if file and File.exists?(file)
    App.info 'Removing', file
    FileUtils.rm file
  end
end

def copy_source_resource(file)
  if File.exists?(file)
    project_file = project_resource file
    project_dir  = File.dirname project_file
    if !Dir.exists?(project_dir)
      App.info 'Creating', project_dir
      FileUtils.mkdir_p project_dir
    end
    App.info 'Copying', "#{File.basename file} to #{project_dir}"
    FileUtils.cp file, project_file
  else
    raise "I should be copying #{file} but it doesn't seem to exist."
  end
end

def resource_needs_updating?(file)
  # check to see if the project's resource is missing or out of date
  !File.exists?(project_resource(file)) || !FileUtils.cmp(file, project_resource(file))
end



##### CTags
## via https://github.com/yury/CTags
##
desc "Generate ctags for sublime"
task :tags do
  config = App.config
  files = config.bridgesupport_files + config.vendor_projects.map { |p| Dir.glob(File.join(p.path, '*.bridgesupport')) }.flatten
  files += Dir.glob(config.project_dir + "/app/**/*").flatten
  files += Dir.glob(config.project_dir + "/spec/**/*").flatten
  tags_config = File.join(config.motiondir, 'data', 'bridgesupport-ctags.cfg')
  sh "ctags --options=\"#{tags_config}\" -f .tags #{files.map { |x| '"' + x + '"' }.join(' ')}"
end