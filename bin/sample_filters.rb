#!/usr/bin/env ruby

require 'json'
require 'find'


out = []
json_file_paths = Find
    .find(ARGV.shift)
    .find_all { |path| path =~ /.*.run_validation_report.json$/ }
    .each do |path|
        file = File.read(path)
        data_hash = JSON.parse(file)
        lane = data_hash["lane"]
        out << ["Lane #{lane}", "show", "L#{lane} |"].join("\t")
    end

puts out if out.length() > 1