# Copyright (C) 2012, HipByte SPRL. All Rights Reserved.
#
# This file is subject to the terms and conditions of the End User License
# Agreement accompanying the package this file is a part of.

require 'thread'

module Motion; module Project;
  class Builder
    include Rake::DSL if Rake.const_defined?(:DSL)

    def build(config, platform)
      datadir = config.datadir
      archs = config.archs(platform)

      ruby = File.join(config.bindir, 'ruby')
      llc = File.join(config.bindir, 'llc')

      if config.spec_mode and config.spec_files.empty?
        App.fail "No spec files in `#{config.specs_dir}'"
      end

      # Locate SDK and compilers.
      sdk = config.sdk(platform)
      cc = config.locate_compiler(platform, 'gcc')
      cxx = config.locate_compiler(platform, 'g++')
    
      build_dir = File.join(config.versionized_build_dir(platform))
      App.info 'Build', build_dir
 
      # Prepare the list of BridgeSupport files needed. 
      bs_files = config.bridgesupport_files

      # Build vendor libraries.
      vendor_libs = []
      config.vendor_projects.each do |vendor_project|
        vendor_project.build(platform)
        vendor_libs.concat(vendor_project.libs)
        bs_files.concat(vendor_project.bs_files)
      end 

      # Build object files.
      objs_build_dir = File.join(build_dir, 'objs')
      FileUtils.mkdir_p(objs_build_dir)
      project_file_changed = File.mtime(config.project_file) > File.mtime(objs_build_dir)
      build_file = Proc.new do |path|
        obj ||= File.join(objs_build_dir, "#{path}.o")
        should_rebuild = (project_file_changed \
            or !File.exist?(obj) \
            or File.mtime(path) > File.mtime(obj) \
            or File.mtime(ruby) > File.mtime(obj))
 
        # Generate or retrieve init function.
        init_func = should_rebuild ? "MREP_#{`/usr/bin/uuidgen`.strip.gsub('-', '')}" : `#{config.locate_binary('nm')} #{obj}`.scan(/T\s+_(MREP_.*)/)[0][0]

        if should_rebuild
          App.info 'Compile', path
          FileUtils.mkdir_p(File.dirname(obj))
          arch_objs = []
          archs.each do |arch|
            # Locate arch kernel.
            kernel = File.join(datadir, platform, "kernel-#{arch}.bc")
            raise "Can't locate kernel file" unless File.exist?(kernel)
   
            # LLVM bitcode.
            bc = File.join(objs_build_dir, "#{path}.#{arch}.bc")
            bs_flags = bs_files.map { |x| "--uses-bs \"" + x + "\" " }.join(' ')
            sh "/usr/bin/env VM_KERNEL_PATH=\"#{kernel}\" #{ruby} #{bs_flags} --emit-llvm \"#{bc}\" #{init_func} \"#{path}\""
   
            # Assembly.
            asm = File.join(objs_build_dir, "#{path}.#{arch}.s")
            llc_arch = case arch
              when 'i386'; 'x86'
              when 'x86_64'; 'x86-64'
              when /^arm/; 'arm'
              else; arch
            end
            sh "#{llc} \"#{bc}\" -o=\"#{asm}\" -march=#{llc_arch} -relocation-model=pic -disable-fp-elim -jit-enable-eh -disable-cfi"
   
            # Object.
            arch_obj = File.join(objs_build_dir, "#{path}.#{arch}.o")
            sh "#{cc} -fexceptions -c -arch #{arch} \"#{asm}\" -o \"#{arch_obj}\""
  
            [bc, asm].each { |x| File.unlink(x) }
            arch_objs << arch_obj
          end
   
          # Assemble fat binary.
          arch_objs_list = arch_objs.map { |x| "\"#{x}\"" }.join(' ')
          sh "/usr/bin/lipo -create #{arch_objs_list} -output \"#{obj}\""
        end

        [obj, init_func]
      end

      # Create builders.
      builders_count =
        if jobs = ENV['jobs']
          jobs.to_i
        else
          `/usr/sbin/sysctl -n machdep.cpu.thread_count`.strip.to_i
        end
      builders_count = 1 if builders_count < 1 
      builders = []
      builders_count.times do
        queue = []
        th = Thread.new do
          sleep
          objs = []
          while path = queue.shift
            objs << build_file.call(path)
          end
          queue.concat(objs)
        end
        builders << [queue, th]
      end

      # Feed builders with work.
      builder_i = 0
      config.ordered_build_files.each do |path|
        builders[builder_i][0] << path
        builder_i += 1
        builder_i = 0 if builder_i == builders_count
      end
 
      # Start build.
      builders.each do |queue, th|
        sleep 0.01 while th.status != 'sleep'
        th.wakeup
      end
      builders.each { |queue, th| th.join }

      # Merge the result (based on build order).
      objs = []
      builder_i = 0
      config.ordered_build_files.each do |path|
        objs << builders[builder_i][0].shift
        builder_i += 1
        builder_i = 0 if builder_i == builders_count
      end

      app_objs = objs
      if config.spec_mode
        # Build spec files too, but sequentially.
        objs << build_file.call(File.expand_path(File.join(File.dirname(__FILE__), '../spec.rb')))
        spec_objs = config.spec_files.map { |path| build_file.call(path) }
        objs += spec_objs
      end

      # Generate main file.
      main_txt = <<EOS
#import <UIKit/UIKit.h>

extern "C" {
    void ruby_sysinit(int *, char ***);
    void ruby_init(void);
    void ruby_init_loadpath(void);
    void ruby_script(const char *);
    void ruby_set_argv(int, char **);
    void rb_vm_init_compiler(void);
    void rb_vm_init_jit(void);
    void rb_vm_aot_feature_provide(const char *, void *);
    void *rb_vm_top_self(void);
    void rb_rb2oc_exc_handler(void);
    void rb_exit(int);
EOS
      objs.each do |_, init_func|
        main_txt << "void #{init_func}(void *, void *);\n"
      end
      main_txt << <<EOS
}
EOS

      if config.spec_mode
        main_txt << <<EOS
@interface SpecLauncher : NSObject
@end

@implementation SpecLauncher

+ (id)launcher
{
    [UIApplication sharedApplication];
    SpecLauncher *launcher = [[self alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:launcher selector:@selector(appLaunched:) name:UIApplicationDidBecomeActiveNotification object:nil];
    return launcher; 
}

- (void)appLaunched:(id)notification
{
    // Give a bit of time for the simulator to attach...
    [self performSelector:@selector(runSpecs) withObject:nil afterDelay:0.1];
}

- (void)runSpecs
{
EOS
        spec_objs.each do |_, init_func|
          main_txt << "#{init_func}(self, 0);\n"
        end
        main_txt << "[NSClassFromString(@\"Bacon\") performSelector:@selector(run)];\n"
        main_txt << <<EOS
}

@end
EOS
      end
      main_txt << <<EOS
int
main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    const char *progname = argv[0];
    ruby_init();
    ruby_init_loadpath();
    ruby_script(progname);
    int retval = 0;
    try {
        void *self = rb_vm_top_self();
EOS
      main_txt << "[SpecLauncher launcher];\n" if config.spec_mode
      app_objs.each do |_, init_func|
        main_txt << "#{init_func}(self, 0);\n"
      end
      main_txt << <<EOS
        retval = UIApplicationMain(argc, argv, nil, @"#{config.delegate_class}");
        rb_exit(retval);
    }
    catch (...) {
	rb_rb2oc_exc_handler();
    }
    [pool release];
    return retval;
}
EOS
 
      # Compile main file.
      main = File.join(objs_build_dir, 'main.mm')
      main_o = File.join(objs_build_dir, 'main.o')
      if !(File.exist?(main) and File.exist?(main_o) and File.read(main) == main_txt)
        File.open(main, 'w') { |io| io.write(main_txt) }
        sh "#{cxx} \"#{main}\" #{config.cflags(platform, true)} -c -o \"#{main_o}\""
      end

      # Prepare bundle.
      bundle_path = config.app_bundle(platform)
      unless File.exist?(bundle_path)
        App.info 'Create', bundle_path
        FileUtils.mkdir_p(bundle_path)
      end

      # Link executable.
      main_exec = config.app_bundle_executable(platform)
      main_exec_created = false
      if !File.exist?(main_exec) \
          or File.mtime(config.project_file) > File.mtime(main_exec) \
          or objs.any? { |path, _| File.mtime(path) > File.mtime(main_exec) } \
	  or File.mtime(main_o) > File.mtime(main_exec) \
          or File.mtime(File.join(datadir, platform, 'libmacruby-static.a')) > File.mtime(main_exec)
        App.info 'Link', main_exec
        objs_list = objs.map { |path, _| path }.unshift(main_o).map { |x| "\"#{x}\"" }.join(' ')
        frameworks = config.frameworks.map { |x| "-framework #{x}" }.join(' ')
        framework_stubs_objs = []
        config.frameworks.each do |framework|
          stubs_obj = File.join(datadir, platform, "#{framework}_stubs.o")
          framework_stubs_objs << "\"#{stubs_obj}\"" if File.exist?(stubs_obj)
        end
        sh "#{cxx} -o \"#{main_exec}\" #{objs_list} #{framework_stubs_objs.join(' ')} #{config.ldflags(platform)} -L#{File.join(datadir, platform)} -lmacruby-static -lobjc -licucore #{frameworks} #{config.libs.join(' ')} #{vendor_libs.map { |x| '-force_load ' + x }.join(' ')}"
        main_exec_created = true
      end

      # Create bundle/Info.plist.
      bundle_info_plist = File.join(bundle_path, 'Info.plist')
      if !File.exist?(bundle_info_plist) or File.mtime(config.project_file) > File.mtime(bundle_info_plist)
        App.info 'Create', bundle_info_plist
        File.open(bundle_info_plist, 'w') { |io| io.write(config.info_plist_data) }
        sh "/usr/bin/plutil -convert binary1 \"#{bundle_info_plist}\""
      end

      # Create bundle/PkgInfo.
      bundle_pkginfo = File.join(bundle_path, 'PkgInfo')
      if !File.exist?(bundle_pkginfo) or File.mtime(config.project_file) > File.mtime(bundle_pkginfo)
        App.info 'Create', bundle_pkginfo
        File.open(bundle_pkginfo, 'w') { |io| io.write(config.pkginfo_data) }
      end

      # Compile IB resources.
      if File.exist?(config.resources_dir)
        ib_resources = []
        ib_resources.concat(Dir.glob(File.join(config.resources_dir, '*.xib')).map { |xib| [xib, xib.sub(/\.xib$/, '.nib')] })
        ib_resources.concat(Dir.glob(File.join(config.resources_dir, '*.storyboard')).map { |storyboard| [storyboard, storyboard.sub(/\.storyboard$/, '.storyboardc')] })
        ib_resources.each do |src, dest|
          if !File.exist?(dest) or File.mtime(src) > File.mtime(dest)
            App.info 'Compile', src
            sh "/usr/bin/ibtool --compile \"#{dest}\" \"#{src}\""
          end
        end
      end

      # Compile CoreData Model resources.
      if File.exist?(config.resources_dir)
        Dir.glob(File.join(config.resources_dir, '*.xcdatamodeld')).each do |model|
          momd = model.sub(/\.xcdatamodeld$/, '.momd')
          if !File.exist?(momd) or File.mtime(model) > File.mtime(momd)
            App.info 'Compile', model
            # sh "\"#{App.config.xcode_dir}/usr/bin/momc\" \"#{model}\" \"#{momd}\""
            # fix for compiling models 
            sh "\"#{App.config.xcode_dir}/usr/bin/momc\" \"#{File.absolute_path(model)}\" \"#{File.absolute_path(momd)}\""
          end
        end
      end

      # Copy resources, handle subdirectories.
      reserved_app_bundle_files = [
        '_CodeSignature/CodeResources', 'CodeResources', 'embedded.mobileprovision',
        'Info.plist', 'PkgInfo', 'ResourceRules.plist',
        config.name
      ]
      resources_files = []
      if File.exist?(config.resources_dir)
        resources_files = Dir.chdir(config.resources_dir) do
          Dir.glob('**/*').reject { |x| ['.xib', '.storyboard', '.xcdatamodeld'].include?(File.extname(x)) }
        end
        resources_files.each do |res|
          res_path = File.join(config.resources_dir, res)
          if reserved_app_bundle_files.include?(res)
            App.fail "Cannot use `#{res_path}' as a resource file because it's a reserved application bundle file"
          end
          dest_path = File.join(bundle_path, res)
          if !File.exist?(dest_path) or File.mtime(res_path) > File.mtime(dest_path)
            FileUtils.mkdir_p(File.dirname(dest_path))
            App.info 'Copy', res_path
            FileUtils.cp_r(res_path, File.dirname(dest_path))
          end
        end
      end

      # Delete old resource files.
      Dir.chdir(bundle_path) do
        Dir.glob('**/*').each do |bundle_res|
          next if File.directory?(bundle_res)
          next if reserved_app_bundle_files.include?(bundle_res)
          next if resources_files.include?(bundle_res)
          App.warn "File `#{bundle_res}' found in app bundle but not in `#{config.resources_dir}', removing"
          FileUtils.rm_rf(bundle_res)
        end
      end

      # Generate dSYM.
      dsym_path = config.app_bundle_dsym(platform)
      if !File.exist?(dsym_path) or File.mtime(main_exec) > File.mtime(dsym_path)
        App.info "Create", dsym_path
        sh "/usr/bin/dsymutil \"#{main_exec}\" -o \"#{dsym_path}\""
      end

      # Strip all symbols. Only in release mode.
      if main_exec_created and config.release?
        App.info "Strip", main_exec
        sh "#{config.locate_binary('strip')} \"#{main_exec}\""
      end
    end

    def codesign(config, platform)
      bundle_path = config.app_bundle(platform)
      raise unless File.exist?(bundle_path)

      # Create bundle/ResourceRules.plist.
      resource_rules_plist = File.join(bundle_path, 'ResourceRules.plist')
      unless File.exist?(resource_rules_plist)
        App.info 'Create', resource_rules_plist
        File.open(resource_rules_plist, 'w') do |io|
          io.write(<<-PLIST)
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>rules</key>
        <dict>
                <key>.*</key>
                <true/>
                <key>Info.plist</key>
                <dict>
                        <key>omit</key>
                        <true/>
                        <key>weight</key>
                        <real>10</real>
                </dict>
                <key>ResourceRules.plist</key>
                <dict>
                        <key>omit</key>
                        <true/>
                        <key>weight</key>
                        <real>100</real>
                </dict>
        </dict>
</dict>
</plist>
PLIST
        end
      end

      # Copy the provisioning profile.
      bundle_provision = File.join(bundle_path, "embedded.mobileprovision")
      if !File.exist?(bundle_provision) or File.mtime(config.provisioning_profile) > File.mtime(bundle_provision)
        App.info 'Create', bundle_provision
        FileUtils.cp config.provisioning_profile, bundle_provision
      end

      # Codesign.
      codesign_cmd = "CODESIGN_ALLOCATE=\"#{File.join(config.platform_dir(platform), 'Developer/usr/bin/codesign_allocate')}\" /usr/bin/codesign"
      if File.mtime(config.project_file) > File.mtime(bundle_path) \
          or !system("#{codesign_cmd} --verify \"#{bundle_path}\" >& /dev/null")
        App.info 'Codesign', bundle_path
        entitlements = File.join(config.versionized_build_dir(platform), "Entitlements.plist")
        File.open(entitlements, 'w') { |io| io.write(config.entitlements_data) }
        sh "#{codesign_cmd} -f -s \"#{config.codesign_certificate}\" --resource-rules=\"#{resource_rules_plist}\" --entitlements #{entitlements} \"#{bundle_path}\""
      end
    end

    def archive(config)
      # Create .ipa archive.
      app_bundle = config.app_bundle('iPhoneOS')
      archive = config.archive
      if !File.exist?(archive) or File.mtime(app_bundle) > File.mtime(archive)
        App.info 'Create', archive
        tmp = "/tmp/ipa_root"
        sh "/bin/rm -rf #{tmp}"
        sh "/bin/mkdir -p #{tmp}/Payload"
        sh "/bin/cp -r \"#{app_bundle}\" #{tmp}/Payload"
        Dir.chdir(tmp) do
          sh "/bin/chmod -R 755 Payload"
          sh "/usr/bin/zip -q -r archive.zip Payload"
        end
        sh "/bin/cp #{tmp}/archive.zip \"#{archive}\""
      end

=begin
      # Create .xcarchive. Only in release mode.
      if config.release?
        xcarchive = File.join(File.dirname(app_bundle), config.name + '.xcarchive')
        if !File.exist?(xcarchive) or File.mtime(app_bundle) > File.mtime(xcarchive)
          App.info 'Create', xcarchive
          apps = File.join(xcarchive, 'Products', 'Applications')
          FileUtils.mkdir_p apps
          sh "/bin/cp -r \"#{app_bundle}\" \"#{apps}\""
          dsyms = File.join(xcarchive, 'dSYMs')
          FileUtils.mkdir_p dsyms
          sh "/bin/cp -r \"#{config.app_bundle_dsym('iPhoneOS')}\" \"#{dsyms}\""
          app_path = "Applications/#{config.name}.app"
          info_plist = {
            'ApplicationProperties' => {
              'ApplicationPath' => app_path,
              'CFBundleIdentifier' => config.identifier,
              'IconPaths' => config.icons.map { |x| File.join(app_path, x) },
            },
            'ArchiveVersion' => 1,
            'CreationDate' => Time.now,
            'Name' => config.name,
            'SchemeName' => config.name
          }
          File.open(File.join(xcarchive, 'Info.plist'), 'w') do |io|
            io.write Motion::PropertyList.to_s(info_plist)
          end 
        end
      end
=end
    end
  end
end; end
