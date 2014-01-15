#!/usr/bin/env ruby

require 'shellwords'
require 'fileutils'
require 'pathname'
require 'set'

#TARGET = "src/alex/test.cpp"
OBJDIR = "obj"
SRCDIR = "src"
DEPDIR = "obj"
BINDIR = "bin"
INCPATH = "-Isrc"

CC      = "g++-4.8"
CCFLAGS = ["-std=c++1y", "-pthread", "-fnon-call-exceptions -g -fsanitize=address", 
           "-Wall", "-Wextra", "-Wno-sign-compare", "-Wno-deprecated"]
LFLAGS  = ["-lrt", "-ldwarf", "-lelf"]

@processed_files = Set.new
@objs = []
@last_mtime = Time::new(0)

def parse_makefile_rules(text)
    rules = text.gsub(/^.*?:/, '').gsub(/\\\n/, '').split()
    return rules
end

def shell(*args)
    #args = args.map{|item| Shellwords.escape(item) }
    cmd = args.join(" ")
    puts cmd
    result = `#{cmd}`
    if $?.exitstatus != 0
        exit(1)
    end
    return result
end

def mtime(file)
    if not File::exists?(file)
        return Time::new(0)
    end
    return File::mtime(file)
end

def strip_suffix(file) 
    return file.sub(/\.[^\/.]+\Z/, '')
end

def cpp2obj(file)
    file = file.sub(SRCDIR+'/', '')
    file = OBJDIR + "/" + strip_suffix(file) + '.o'
    return file
end

def build_cpp(cppfile)
    objfile = cpp2obj(cppfile)
    objdir = File::dirname(objfile)
    if not File::exists?(objdir)
        FileUtils::mkdir_p(objdir)
    end
    shell(CC, *CCFLAGS, *INCPATH, "-o"+objfile, "-c", cppfile)
    @last_mtime = Time::now()
    
end

def process_file(file)
    if file.end_with?(".h")
        process_h(file)
    else
        print "uknown file type"
    end
end

def process_h(hfile)
    hfile = Pathname.new(hfile).cleanpath.to_s
    
    if @processed_files.include?(hfile)
        return
    else
        @processed_files.add(hfile)
    end
    
#     puts "  >> process hfile #{hfile}"
    file = strip_suffix(hfile)
    
    if File::exists?(file + ".cpp") 
        process_cpp(file + ".cpp")
    end
    
    if File::directory?(file)
        files = Dir::glob(file + "/*.cpp")
        for cppfile in files 
            process_cpp(cppfile)
        end
        
    end
    
    if File::basename(hfile) == "PKG.h"
        files = Dir::glob(File::dirname(hfile) + "/*.cpp")
        for cppfile in files
            process_cpp(cppfile)
        end
    end
end

def get_makefile_rules(cppfile)
    file = strip_suffix(cppfile.sub(SRCDIR+"/", ''))
    depfile = DEPDIR + "/" + file + ".dep"
    
    if not File::exists?(depfile) or mtime(cppfile) >= mtime(depfile)
        dir = File::dirname(depfile)
        if not File::exists?(dir)
            FileUtils::mkdir_p(dir)
        end
        shell(CC, "-MM", "-MT"+cppfile, *CCFLAGS, *INCPATH, cppfile, ">", depfile)
    end
    
    rules = parse_makefile_rules(IO::read(depfile))
end

def process_cpp(cppfile)
    cppfile = Pathname.new(cppfile).cleanpath.to_s
    
    if @processed_files.include?(cppfile)
        return
    else
        @processed_files.add(cppfile)
    end
    
#     puts "  >> process cpp #{cppfile}"
    file = strip_suffix(cppfile.sub(SRCDIR+"/", ''))
    objfile = "#{OBJDIR}/#{file}.o"
    #cppfile = "#{SRCDIR}/#{file}"
    
    rules = get_makefile_rules(cppfile)
    
    buildtime = mtime(cpp2obj(cppfile))
    if buildtime > @last_mtime
        @last_mtime = buildtime
    end
    need_update = false
    
    for rule in rules
        if rule != cppfile
            process_file(rule)
        end
        currmtime = mtime(rule)
        if (currmtime > buildtime) 
            #puts "need to build #{cppfile} due to #{rule}"
            need_update = true
        end
        #puts "rules #{rule}"
    end
    
    @objs << cpp2obj(cppfile)
    if need_update
        build_cpp(cppfile)
        return true
    end
    return false
end

if ARGV.size != 1 
    warn "Usage: #{$0} file.cpp"
    exit(1)
end

ROOT   = File::dirname($0)
TARGET = File::absolute_path(ARGV[0]).sub(File::absolute_path(ROOT) + "/", '')

if ROOT != "."
    Dir::chdir(ROOT)
else
    
end

process_cpp(TARGET)

ofile = File::basename(TARGET, ".cpp")
FileUtils::mkdir_p(BINDIR)
if @last_mtime >= mtime(ofile)
    shell(CC, *CCFLAGS, "-o"+BINDIR+"/"+ofile, *@objs, *LFLAGS)
end
    


