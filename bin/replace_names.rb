#!/usr/bin/env ruby

require 'json'
require 'find'

outpath = ARGV.shift

json_file_paths = Find
    .find(outpath)
    .find_all { |path| path =~ /.*.run_validation_report.json$/ }
    .each do |path|
        file = File.read(path)
        data_hash = JSON.parse(file)
        version = data_hash["version"]
        case version
        when "3.0"
            data_hash["readsets"].each do |name, sections|
                values = sections["barcodes"].first
                library = values["LIBRARY"]
                search_string = name.sub(/_#{library}/, ".#{library}")
                puts [search_string, name].join("\t")
            end
        when "2.0"
            data_hash["readsets"].each do |name, sections|
                values = sections["barcodes"].first
                library = values["LIBRARY"]
                search_string = name.sub(/_#{library}/, ".#{library}")
                puts [search_string, name].join("\t")
            end
        else
            data_hash["barcodes"]
            .each do |name, sections|
                values = sections.first
                library = values["LIBRARY"]
                search_string = name.sub(/_#{library}/, ".#{library}")
                puts [search_string, name].join("\t")
            end
        end
    end
