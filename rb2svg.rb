#!/usr/bin/env ruby
# coding: utf-8

require 'fileutils'
load 'a.rb'

$cff_fonts.each_pair do |fontname, font|
  dirname = fontname.to_s + '.d'
  FileUtils.rm_r dirname if File.exists? dirname
  FileUtils.mkdir(dirname, {:mode => 0775})
  font[:glyphs].each_pair do |id, glyph|
    ybias = font[:parameters][:bbox][3]
    target = File.new dirname + "/" + id.to_s + ".svg", 'w'
    target <<<<-EOC
<svg viewBox='0 0 #{font[:parameters][:bbox][2] - font[:parameters][:bbox][0]} #{font[:parameters][:bbox][3] - font[:parameters][:bbox][1]}' xmlns='http://www.w3.org/2000/svg' version='1.1'>
  <path fill='none' stroke='black' d='
    EOC
    glyph[:commands].each do |path|
      case path[:command]
        when :line
          target <<<<-EOC
    M #{path[:s][0]},#{ybias - path[:s][1]} L #{path[:e][0]},#{ybias - path[:e][1]}
          EOC
        when :curve
          target <<<<-EOC
    M #{path[:s][0]},#{ybias - path[:s][1]} C #{path[:b0][0]},#{ybias - path[:b0][1]} #{path[:b1][0]},#{ybias - path[:b1][1]} #{path[:e][0]},#{ybias - path[:e][1]}
          EOC
      end
    end
    target <<<<-EOC
  '/>
</svg>
    EOC
  end
end
