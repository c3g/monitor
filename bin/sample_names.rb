#!/usr/bin/env ruby

require 'json'
require 'find'
require 'pp'

puts ["Full names", "Simple", "Simple | Index name"].join("\t")

json_file_paths = Find
    .find(ARGV.shift)
    .find_all { |path| path =~ /.*.run_validation_report.json$/ }
    .each do |path|
        file = File.read(path)
        data_hash = JSON.parse(file)
        version = data_hash["version"]
        case version
        when "3.0"
            data_hash["readsets"] \
            .each do |name, sections|
                values = sections["barcodes"].first
                library = values["LIBRARY"]
                indexname = values["INDEX_NAME"]
                puts [name, name.sub(/_#{library}/,''), name.sub(/_#{library}/," | #{indexname}")].join("\t")
            end
        when "2.0"
            data_hash["readsets"] \
            .each do |name, sections|
                values = sections["barcodes"].first
                library = values["LIBRARY"]
                indexname = values["INDEX_NAME"]
                puts [name, name.sub(/_#{library}/,''), name.sub(/_#{library}/," | #{indexname}")].join("\t")
            end
        else
            data_hash["barcodes"]
            .each do |name, values|
                values = values.first
                library = values["LIBRARY"]
                indexname = values["INDEX_NAME"]
                puts [name, name.sub(/_#{library}/,''), name.sub(/_#{library}/," | #{indexname}")].join("\t")
            end
        end
    end
