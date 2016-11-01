#!/usr/bin/env ruby
# coding: utf-8
# Copyright 2016 pixie-grasper

require 'getoptlong.rb'

$default_output_file_name = 'a.rb'

def usage
  print <<-EOM
Usage: cff2rb [command]... fontfile.cff...

 commands:
  -o, --output    specify output file name
                  default: #{$default_output_file_name}
  -f, --force     force output mode
                  if file exists, it will overwrites
  EOM
  exit
end

def main
  options = {}
  begin
    GetoptLong.new.set_options(
      %w/-f --force/ << GetoptLong::NO_ARGUMENT,
      %w/-o --output/ << GetoptLong::REQUIRED_ARGUMENT,
    ).each_option do |name, value|
      options[name.sub(/^--?/,'').gsub(/-/,'_').to_sym] = value
    end
  rescue GetoptLong::Error
    usage
  end
  if ARGV.length == 0 then
    usage
  end
  if not options.member? :o then
    options[:o] = $default_output_file_name
  end
  if File.exists? options[:o] and not options.member? :f then
    puts "output file #{options[:o]} exists"
    puts 'do nothing'
    exit
  end

  begin
    ruby = convert_cffs_to_ruby ARGV
    File.new(options[:o], 'w').write ruby
  rescue => e
    puts e
    puts e.backtrace
    puts 'do nothing'
  end
end

def convert_cffs_to_ruby(filenames)
  ret = <<-EOC
#!/usr/bin/env ruby
# coding: utf-8

unless defined? CFF
  CFF = :defined

  $cff_fonts = {}
end

  EOC
  filenames.each do |filename|
    ret.puts! convert_cff_to_ruby filename
  end
  return ret
end

def convert_cff_to_ruby(filename)
  puts "converting #{filename} ..."
  return CFF.new File.open filename
end

class String
  def puts!(*args)
    args.each do |item|
      self << item.to_s << $/
    end
  end

  def to_a
    ret = []
    for i in 0 ... self.length do
      ret[i] = self[i].ord
    end
    return ret
  end
end

class CFF
  def initialize(file)
    @source = file
    file.autoclose = true
    seek_file
    data_begin = file.pos
    header = read_header
    name_index = read_INDEX
    @top_dict = TopDICT.new read_INDEX[0]
    @string_index = @@standard_strings + read_INDEX
    @global_subroutines_index = read_INDEX.map { |command|
      parse command.to_a
    }
    file.seek data_begin + @top_dict.CharStrings
    char_strings_index = read_INDEX
    file.seek data_begin + @top_dict.charset
    charsets = read_charsets char_strings_index.length
    @glyphs = {}
    for i in 0 ... char_strings_index.length do
      raise "broken file detected." if @glyphs.member? charsets[i]
      @glyphs[charsets[i]] = parse char_strings_index[i].to_a
    end
    if @top_dict.Private then
      file.seek data_begin + @top_dict.Private[1]
      @private_dict = PrivateDICT.new file.read @top_dict.Private[0]
      if @private_dict.Subrs then
        file.seek data_begin + @top_dict.Private[1] + @private_dict.Subrs
        @subroutines_index = read_INDEX.map { |command|
          parse command.to_a
        }
      end
    end
  end

  def to_s
    ret = <<-EOC
glyphs = {}

##
    EOC
    @glyphs.each_pair do |id, glyph|
      ret << <<-EOC
glyphs[:#{@string_index[id].gsub(/\./, '_')}] = #{Render.new(id, glyph, @private_dict, @subroutines_index || [], @global_subroutines_index).to_s}
      EOC
    end
    ret << <<-EOC
##

$cff_fonts[:#{@string_index[@top_dict.FullName].gsub(/[-!"\#$&'*+,.:;=?@^`| ]/, '_').to_sym}] = {
  :glyphs => glyphs,
  :parameters => {
    :bbox => #{@top_dict.FontBBox}
  }
}
    EOC
    return ret
  end

 private
  class TopDICT
    attr_accessor :version, :Notice, :Copyright, :FullName, :FamilyName, :Weight
    attr_accessor :isFixedPitch, :ItalicAngle, :UnderlinePosition, :UnderlineThickness
    attr_accessor :PaintType, :CharstringType, :FontMatrix, :UniqueID, :FontBBox
    attr_accessor :StrokeWidth, :XUID, :charset, :Encoding, :CharStrings, :Private
    attr_accessor :SyntheticBase, :PostScript, :BaseFontName, :BaseFontBlend

    def initialize(index)
      @isFixedPitch = false
      @ItalicAngle = 0
      @UnderlinePosition = -100
      @UnderlineThickness = 50
      @PaintType = 0
      @CharstringType = 2
      @FontMatrix = [0.001, 0, 0, 0.001, 0, 0]
      @FontBBox = [0, 0, 0, 0]
      @StrokeWidth = 0
      @charset = 0
      @Encoding = 0
      buffer = index.to_a
      stack = []
      while not buffer.empty? do
        b0 = buffer.shift
        case b0
          when 32 .. 246
            stack.push(b0 - 139)
          when 247 .. 250
            b1 = buffer.shift
            stack.push((b0 - 247) * 256 + b1 + 108)
          when 251 .. 254
            b1 = buffer.shift
            stack.push(-(b0 - 251) * 256 - b1 - 108)
          when 28
            b1 = buffer.shift
            b2 = buffer.shift
            v = b1 << 8 | b2
            v -= 2 ** 16 if v > 2 ** 15 - 1
            stack.push v
          when 29
            b1 = buffer.shift
            b2 = buffer.shift
            b3 = buffer.shift
            b4 = buffer.shift
            v = b1 << 24 | b2 << 16 | b3 << 8 | b4
            v -= 2 ** 32 if v > 2 ** 31 - 1
            stack.push v
          when 30
            s = ''
            nibbles = []
            loop do
              nibbles = byte_to_nibbles buffer.shift if nibbles.empty?
              n = nibbles.shift
              case n
                when 0 .. 9
                  s << n.to_s
                when 10
                  s << '.'
                when 11
                  s << 'E'
                when 12
                  s << 'E-'
                when 14
                  s << '-'
                when 15
                  break
                else
                  raise 'reserved format detected.'
              end
            end
            stack.push s.to_f
          when 0
            @version = stack.pop
          when 1
            @Notice = stack.pop
          when 2
            @FullName = stack.pop
          when 3
            @FamilyName = stack.pop
          when 4
            @Weight = stack.pop
          when 5
            @FontBBox = stack.pop 4
          when 12
            case buffer.shift
              when 0
                @Copyright = stack.pop
              when 1
                @isFixedPitch = !!stack.pop
              when 2
                @ItalicAngle = stack.pop
              when 3
                @UnderlinePosition = stack.pop
              when 4
                @UnderlineThickness = stack.pop
              when 5
                @PaintType = stack.pop
              when 6
                @CharstringType = stack.pop
              when 7
                @FontMatrix = stack.pop 6
              when 8
                @StrokeWidth = stack.pop
              when 20
                @SyntheticBase = stack.pop
              when 21
                @PostScript = stack.pop
              when 22
                @BaseFontName = stack.pop
              when 23
                @BaseFontBlend = [stack[0]]
                for i in 1 ... stack.length do
                  @BaseFontBlend[i] = @BaseFontBlend[i - 1] - stack[i]
                end
                stack = []
              when 30 .. 38
                raise 'CID-Font extension detected.'
              else
                raise 'unknown extension detected.'
            end
          when 13
            @UniqueID = stack.pop
          when 14
            @XUID = stack
            stack = []
          when 15
            @charset = stack.pop
          when 16
            @Encoding = stack.pop
          when 17
            @CharStrings = stack.pop
          when 18
            @Private = stack.pop 2
          else
            raise 'unknown extension detected.'
        end
      end
      raise "broken TopDICT detected." if not stack.empty?
    end

    def to_s
      {
        :version => @version,
        :Notice => @Notice,
        :Copyright => @Copyright,
        :FullName => @FullName,
        :FamilyName => @FamilyName,
        :Weight => @Weight,
        :isFixedPitch => @isFixedPitch,
        :ItalicAngle => @ItalicAngle,
        :UnderlinePosition => @UnderlinePosition,
        :UnderlineThickness => @UnderlineThickness,
        :PaintType => @PaintType,
        :CharstringType => @CharstringType,
        :FontMatrix => @FontMatrix,
        :UniqueID => @UniqueID,
        :FontBBox => @FontBBox,
        :StrokeWidth => @StrokeWidth,
        :XUID => @XUID,
        :charset => @charset,
        :Encoding => @Encoding,
        :CharStrings => @CharStrings,
        :Private => @Private,
        :SyntheticBase => @SyntheticBase,
        :PostScript => @PostScript,
        :BaseFontName => @BaseFontName,
        :BaseFontBlend => @BaseFontBlend
      }.to_s
    end

   private
    def byte_to_nibbles(byte)
      return [byte >> 4, byte & 15]
    end
  end

  class PrivateDICT
    attr_accessor :BlueValues, :OtherBlues, :FamilyBlues, :FamilyOtherBlues, :Blue
    attr_accessor :BlueScale, :BlueShift, :BlueFuzz, :StdHW, :StdVW, :StemSnapH
    attr_accessor :StemSnapV, :ForceBold, :LanguageGroup, :ExpansionFactor, :initialRandomSeed
    attr_accessor :Subrs, :defaultWidthX, :nominalWidthX

    def initialize(dict)
      @BlueScale = 0.039625
      @BlueShift = 7
      @BlueFuzz = 1
      @ForceBold = false
      @LanguageGroup = 0
      @ExpansionFactor = 0.06
      @initialRandomSeed = 0
      @defaultWidthX = 0
      @nominalWidthX = 0
      buffer = dict.to_a
      stack = []
      while not buffer.empty? do
        b0 = buffer.shift
        case b0
          when 32 .. 246
            stack.push(b0 - 139)
          when 247 .. 250
            b1 = buffer.shift
            stack.push((b0 - 247) * 256 + b1 + 108)
          when 251 .. 254
            b1 = buffer.shift
            stack.push(-(b0 - 251) * 256 - b1 - 108)
          when 28
            b1 = buffer.shift
            b2 = buffer.shift
            v = b1 << 8 | b2
            v -= 2 ** 16 if v > 2 ** 15 - 1
            stack.push v
          when 29
            b1 = buffer.shift
            b2 = buffer.shift
            b3 = buffer.shift
            b4 = buffer.shift
            v = b1 << 24 | b2 << 16 | b3 << 8 | b4
            v -= 2 ** 32 if v > 2 ** 31 - 1
            stack.push v
          when 30
            s = ''
            nibbles = []
            loop do
              nibbles = byte_to_nibbles buffer.shift if nibbles.empty?
              n = nibbles.shift
              case n
                when 0 .. 9
                  s << n.to_s
                when 10
                  s << '.'
                when 11
                  s << 'E'
                when 12
                  s << 'E-'
                when 14
                  s << '-'
                when 15
                  break
                else
                  raise 'reserved format detected.'
              end
            end
            stack.push s.to_f
          when 6
            @BlueValues = [stack[0]]
            for i in 1 ... stack.length do
              @BlueValues[i] = @BlueValues[i - 1] - stack[i]
            end
            stack = []
          when 7
            @OtherBlues = [stack[0]]
            for i in 1 ... stack.length do
              @OtherBlues[i] = @OtherBlues[i - 1] - stack[i]
            end
            stack = []
          when 8
            @FamilyBlues = [stack[0]]
            for i in 1 ... stack.length do
              @FamilyBlues[i] = @FamilyBlues[i - 1] - stack[i]
            end
            stack = []
          when 9
            @FamilyOtherBlues = [stack[0]]
            for i in 1 ... stack.length do
              @FamilyOtherBlues[i] = @FamilyOtherBlues[i - 1] - stack[i]
            end
            stack = []
          when 10
            @StdHW = stack.pop
          when 11
            @StdVW = stack.pop
          when 12
            case buffer.shift
              when 9
                @BlueScale = stack.pop
              when 10
                @BlueShift = stack.pop
              when 11
                @BlueFuzz = stack.pop
              when 12
                @StemSnapH = [stack[0]]
                for i in 1 ... stack.length do
                  @StemSnapH[i] = @StemSnapH[i - 1] - stack[i]
                end
                stack = []
              when 13
                @StemSnapV = [stack[0]]
                for i in 1 ... stack.length do
                  @StemSnapV[i] = @StemSnapV[i - 1] - stack[i]
                end
                stack = []
              when 14
                @ForceBold = !!stack.pop
              when 17
                @LanguageGroup = stack.pop
              when 18
                @ExpansionFactor = stack.pop
              when 19
                @initialRandomSeed = stack.pop
              else
                raise 'unknown extension detected.'
            end
          when 19
            @Subrs = stack.pop
          when 20
            @defaultWidthX = stack.pop
          when 21
            @nominalWidthX = stack.pop
          else
            raise 'unknown extension detected.'
        end
      end
      raise "broken TopDICT detected." if not stack.empty?
    end

    def to_s
      {
        :BlueValues => @BlueValues,
        :OtherBlues => @OtherBlues,
        :FamilyBlues => @FamilyBlues,
        :FamilyOtherBlues => @FamilyOtherBlues,
        :Blue => @Blue,
        :BlueScale => @BlueScale,
        :BlueShift => @BlueShift,
        :BlueFuzz => @BlueFuzz,
        :StdHW => @StdHW,
        :StdVW => @StdVW,
        :StemSnapH => @StemSnapH,
        :StemSnapV => @StemSnapV,
        :ForceBold => @ForceBold,
        :LanguageGroup => @LanguageGroup,
        :ExpansionFactor => @ExpansionFactor,
        :initialRandomSeed => @initialRandomSeed,
        :Subrs => @Subrs,
        :defaultWidthX => @defaultWidthX,
        :nominalWidthX => @nominalWidthX
      }.to_s
    end

   private
    def byte_to_nibbles(byte)
      return [byte >> 4, byte & 15]
    end
  end

  class Render
    def initialize(id, glyph, priv_dict, subroutines_index, global_subroutines_index)
      @id = id
      @glyph = glyph
      @private_dict = priv_dict
      @subroutines_index = subroutines_index
      case @subroutines_index.length
        when 0 ... 1240
          @subroutine_bias = 107
        when 1240 ... 33900
          @subroutine_bias = 1131
        else
          @subroutine_bias = 32768
      end
      @global_subroutines_index = global_subroutines_index
      case @global_subroutines_index.length
        when 0 ... 1240
          @global_subroutine_bias = 107
        when 1240 ... 33900
          @global_subroutine_bias = 1131
        else
          @global_subroutine_bias = 32768
      end
      @transient_array = {}
    end

    def to_s
      @history = []
      call_stack = []
      data_stack = []
      job = @glyph
      ip = 0
      @cx = 0
      @cy = 0
      last_moveto = nil
      width = @private_dict.nominalWidthX
      data_stack_has_cleared = false
      loop do
        it = job[ip]
        ip += 1
        if it.class == Symbol then
          case it
            # 4.1 Path Construction Operators
            when :rmoveto
              if not data_stack_has_cleared and data_stack.length > 2 then
                width += data_stack.shift
              end
              closepath last_moveto
              @cx += data_stack.shift
              @cy += data_stack.shift
              last_moveto = [@cx, @cy]
              data_stack.clear
              data_stack_has_cleared = true
            when :hmoveto
              if not data_stack_has_cleared and data_stack.length > 1 then
                width += data_stack.shift
              end
              closepath last_moveto
              @cx += data_stack.shift
              last_moveto = [@cx, @cy]
              data_stack.clear
              data_stack_has_cleared = true
            when :vmoveto
              if not data_stack_has_cleared and data_stack.length > 1 then
                width += data_stack.shift
              end
              closepath last_moveto
              @cy += data_stack.shift
              last_moveto = [@cx, @cy]
              data_stack.clear
              data_stack_has_cleared = true
            when :rlineto
              assert data_stack_has_cleared
              assert data_stack.length % 2 == 0
              data_stack.each_slice 2 do |d|
                lineto d[0], d[1]
              end
              data_stack.clear
            when :hlineto
              assert data_stack_has_cleared
              assert data_stack.length >= 1
              case data_stack.length % 2
                when 0 # {dxa dyb}+
                  data_stack.each_slice 2 do |d|
                    lineto d[0], 0
                    lineto 0, d[1]
                  end
                when 1 # dx1 {dya dxb}*
                  lineto data_stack.shift, 0
                  data_stack.each_slice 2 do |d|
                    lineto 0, d[0]
                    lineto d[1], 0
                  end
              end
              data_stack.clear
            when :vlineto
              assert data_stack_has_cleared
              assert data_stack.length >= 1
              case data_stack.length % 2
                when 0 # {dya dxb}+
                  data_stack.each_slice 2 do |d|
                    lineto 0, d[0]
                    lineto d[1], 0
                  end
                when 1 # dy1 {dxa dyb}*
                  lineto 0, data_stack.shift
                  data_stack.each_slice 2 do |d|
                    lineto d[0], 0
                    lineto 0, d[1]
                  end
              end
              data_stack.clear
            when :rrcurveto
              assert data_stack_has_cleared
              assert data_stack.length % 6 == 0
              data_stack.each_slice 6 do |d|
                curveto *d
              end
              data_stack.clear
            when :hhcurveto
              assert data_stack_has_cleared
              assert data_stack.length >= 4
              case data_stack.length % 4
                when 0 # {dxa dxb dyb dxc}+
                  data_stack.each_slice 4 do |d|
                    curveto d[0], 0, d[1], d[2], d[3], 0
                  end
                when 1 # dy1 {dxa dxb dyb dxc}+
                  curveto data_stack[1], data_stack[0], data_stack[2], data_stack[3], data_stack[4], 0
                  data_stack.shift 5
                  data_stack.each_slice 4 do |d|
                    curveto d[0], 0, d[1], d[2], d[3], 0
                  end
                else
                  assert!
              end
              data_stack.clear
            when :hvcurveto
              assert data_stack_has_cleared
              assert data_stack.length >= 4
              case data_stack.length % 8
                when 0 # {dxa dxb dyb dyc dyd dxe dye dxf}+
                  data_stack.each_slice 8 do |d|
                    curveto d[0], 0, d[1], d[2], 0, d[3]
                    curveto 0, d[4], d[5], d[6], d[7], 0
                  end
                when 1 # {dxa dxb dyb dyc dyd dxe dye dxf}+ dyf
                  data_stack[0 ... -9].each_slice do |d|
                    curveto d[0], 0, d[1], d[2], 0, d[3]
                    curveto 0, d[4], d[5], d[6], d[7], 0
                  end
                  curveto data_stack[-9], 0, data_stack[-8], data_stack[-7], 0, data_stack[-6]
                  curveto 0, data_stack[-5], data_stack[-4], data_stack[-3], data_stack[-2], data_stack[-1]
                when 4 # dx1 dx2 dy2 dy3 {dya dxb dyb dxc dxd dxe dye dyf}*
                  data_stack[0 ... -4].each_slice 8 do |d|
                    curveto d[0], 0, d[1], d[2], 0, d[3]
                    curveto 0, d[4], d[5], d[6], d[7], 0
                  end
                  curveto data_stack[-4], 0, data_stack[-3], data_stack[-2], 0, data_stack[-1]
                when 5 # dx1 dx2 dy2 dy3 {dya dxb dyb dxc dxd dxe dye dyf}* dxf
                  data_stack[0 ... -5].each_slice 8 do |d|
                    curveto d[0], 0, d[1], d[2], 0, d[3]
                    curveto 0, d[4], d[5], d[6], d[7], 0
                  end
                  curveto data_stack[-5], 0, data_stack[-4], data_stack[-3], data_stack[-1], data_stack[-2]
                else
                  assert!
              end
              data_stack.clear
            when :rcurveline
              assert data_stack_has_cleared
              assert data_stack.length >= 8
              assert data_stack.length % 6 != 2
              data_stack[0 ... -2].each_slice 6 do |d|
                curveto *d
              end
              lineto data_stack[-2], data_stack[-1]
              data_stack.clear
            when :rlinecurve
              assert data_stack_has_cleared
              assert data_stack.length >= 8
              assert data_stack.length % 6 != 2
              data_stack[0 ... -6].each_slice 2 do |d|
                lineto *d
              end
              curveto *data_stack[-6 .. -1]
              data_stack.clear
            when :vhcurveto
              assert data_stack_has_cleared
              assert data_stack.length >= 4
              case data_stack.length % 8
                when 0 # {dya dxb dyb dxc dxd dxe dye dyf}+
                  data_stack.each_slice 8 do |d|
                    curveto 0, d[0], d[1], d[2], d[3], 0
                    curveto d[4], 0, d[5], d[6], 0, d[7]
                  end
                when 1 # {dya dxb dyb dxc dxd dxe dye dyf}+ dxf
                  data_stack[0 ... -9].each_slice 8 do |d|
                    curveto 0, d[0], d[1], d[2], d[3], 0
                    curveto d[4], 0, d[5], d[6], 0, d[7]
                  end
                  curveto 0, data_stack[-9], data_stack[-8], data_stack[-7], data_stack[-6], 0
                  curveto data_stack[-5], 0, data_stack[-4], data_stack[-3], data_stack[-1], data_stack[-2]
                when 4 # dy1 dx2 dy2 dx3 {dxa dxb dyb dyc dyd dxe dye dxf}*
                  data_stack[0 ... -4].each_slice 8 do |d|
                    curveto 0, d[0], d[1], d[2], d[3], 0
                    curveto d[4], 0, d[5], d[6], 0, d[7]
                  end
                  curveto 0, data_stack[-4], data_stack[-3], data_stack[-2], data_stack[-1], 0
                when 5 # dy1 dx2 dy2 dx3 {dxa dxb dyb dyc dyd dxe dye dxf}* dyf
                  data_stack[0 ... -5].each_slice 8 do |d|
                    curveto 0, d[0], d[1], d[2], d[3], 0
                    curveto d[4], 0, d[5], d[6], 0, d[7]
                  end
                  curveto 0, data_stack[-5], data_stack[-4], data_stack[-3], data_stack[-2], data_stack[-1]
                else
                  raise 'broken glyph detected.'
              end
              data_stack.clear
            when :vvcurveto
              assert data_stack_has_cleared
              assert data_stack.length >= 4
              case data_stack.length % 4
                when 0 # {dya dxb dyb dyc}+
                  data_stack.each_slice 4 do |d|
                    curveto 0, d[0], d[1], d[2], 0, d[3]
                  end
                when 1 # dx1 {dya dxb dyb dyc}+
                  curveto data_stack[0], data_stack[1], data_stack[2], data_stack[3], 0, data_stack[4]
                  data_stack[5 .. -1].each_slice 4 do |d|
                    curveto 0, d[0], d[1], d[2], 0, d[3]
                  end
              end
              data_stack.clear
            when :flex # XXX
              assert data_stack_has_cleared
              assert data_stack.length == 13
              sorry! :flex
              data_stack.clear
            when :hflex # XXX
              assert data_stack_has_cleared
              assert data_stack.length == 9
              sorry! :hflex
              data_stack.clear
            when :hflex1 # XXX
              assert data_stack_has_cleared
              assert data_stack.length == 9
              sorry! :hflex1
              data_stack.clear
            when :flex1 # XXX
              assert data_stack_has_cleared
              assert data_stack.length == 9
              sorry! :flex1
              data_stack.clear
            # 4.2 Operator for Finishing a Path
            when :endchar
              if not data_stack_has_cleared and data_stack.length > 0 then
                width += data_stack.shift
              end
              closepath last_moveto
              data_stack_has_cleared = true
              break
            # 4.3 Hint Operators
            when :hstem # FIXME
              if not data_stack_has_cleared and data_stack.length > 0 then
                width += data_stack.shift
              end
              data_stack_has_cleared = true
              data_stack.clear
            when :vstem # FIXME
              if not data_stack_has_cleared and data_stack.length > 0 then
                width += data_stack.shift
              end
              data_stack_has_cleared = true
              data_stack.clear
            when :hstemhm # FIXME
              if not data_stack_has_cleared and data_stack.length > 0 then
                width += data_stack.shift
              end
              data_stack_has_cleared = true
              data_stack.clear
            when :vstemhm # FIXME
              if not data_stack_has_cleared and data_stack.length > 0 then
                width += data_stack.shift
              end
              data_stack_has_cleared = true
              data_stack.clear
            when :hintmask # FIXME
              if not data_stack_has_cleared and data_stack.length > 0 then
                width += data_stack.shift
              end
              data_stack_has_cleared = true
              data_stack.clear
            when :contrmask # FIXME
              if not data_stack_has_cleared and data_stack.length > 0 then
                width += data_stack.shift
              end
              data_stack_has_cleared = true
              data_stack.clear
            # 4.4 Arithmetic Operators
            when :abs
              assert data_stack.length >= 1
              data_stack[-1] = data_stack[-1].abs
            when :add
              assert data_stack.length >= 2
              num2 = data_stack.pop
              num1 = data_stack.pop
              data_stack.push num1 + num2
            when :sub
              assert data_stack.length >= 2
              num2 = data_stack.pop
              num1 = data_stack.pop
              data_stack.push num1 - num2
            when :div
              assert data_stack.length >= 2
              num2 = data_stack.pop
              num1 = data_stack.pop
              data_stack.push num1.to_f / num2.to_f
            when :neg
              assert data_stack.length >= 1
              data_stack[-1] = -data_stack[-1]
            when :random # XXX
              sorry! :random
            when :mul
              assert data_stack.length >= 2
              num2 = data_stack.pop
              num1 = data_stack.pop
              data_stack.push num1.to_f * num2.to_f
            when :sqrt
              assert data_stack.length >= 1
              data_stack[-1] = data_stack[-1].to_f ** 0.5
            when :drop
              assert data_stack.length >= 1
              num = data_stack.pop
              assert data_stack.length >= num
              data_stack.pop num
            when :exch
              assert data_stack.length >= 2
              num2 = data_stack.pop
              num1 = data_stack.pop
              data_stack.push num2
              data_stack.push num1
            when :index
              assert data_stack.length >= 1
              i = data_stack.pop
              i = 0 if i < 0
              data_stack.push data_stack[-1 - i]
            when :roll
              assert data_stack.length >= 2
              j = data_stack.pop
              n = data_stack.pop
              a = data_stack.pop n
              for i in 1 .. a.length do
                data_stack.push a[(j - i) % n]
              end
            when :dup
              assert data_stack.length >= 1
              data_stack.push data_stack[-1]
            # 4.5 Storage Operators
            when :put
              assert data_stack.length >= 2
              i = data_stack.pop
              val = data_stack.pop
              @transient_array[i] = val
            when :get
              assert data_stack.length >= 1
              i = data_stack.pop
              data_stack.push @transient_array[i]
            # 4.6 Conditional Operators
            when :and
              assert data_stack.length >= 2
              num2 = data_stack.pop
              num1 = data_stack.pop
              if num1 != 0 and num2 != 0 then
                data_stack.push 1
              else
                data_stack.push 0
              end
            when :or
              assert data_stack.length >= 2
              num2 = data_stack.pop
              num1 = data_stack.pop
              if num1 != 0 or num2 != 0 then
                data_stack.push 1
              else
                data_stack.push 0
              end
            when :not
              assert data_stack.length >= 1
              if data_stack.pop == 0 then
                data_stack.push 1
              else
                data_stack.push 0
              end
            when :eq
              assert data_stack.length >= 2
              num2 = data_stack.pop
              num1 = data_stack.pop
              if num1 == num2 then
                data_stack.push 1
              else
                data_stack.push 0
              end
            when :ifelse
              assert data_stack.length >= 4
              v2 = data_stack.pop
              v1 = data_stack.pop
              s2 = data_stack.pop
              s1 = data_stack.pop
              if v1 <= v2 then
                data_stack.push s1
              else
                data_stack.push s2
              end
            # 4.7 Subroutine Operators
            when :callsubr
              assert data_stack.length >= 1
              call_stack.push [job, ip]
              job = @subroutines_index[data_stack.pop + @subroutine_bias]
              ip = 0
            when :callgsubr
              assert data_stack.length >= 1
              call_stack.push [job, ip]
              job = @global_subroutines_index[data_stack.pop + @global_subroutine_bias]
              ip = 0
            when :return
              assert call_stack.length >= 1
              pair = call_stack.pop
              job = pair[0]
              ip = pair[1]
            else
              raise it.to_s
          end
        else
          data_stack.push it
        end
      end
      if not data_stack.empty? then
        # raise "broken glyph detected."
      end
      return {
        :id => @id,
        :width => width,
        :commands => @history
      }.to_s
    end

   private
    def assert(condition)
      assert! unless condition
    end

    def assert!
      raise 'broken glyph detected.'
    end

    def sorry!(command)
      raise "sorry, #{command} command is not supported."
    end

    def lineto(dx, dy)
      @history << {
        :command => :line,
        :s => [@cx, @cy],
        :e => [@cx + dx, @cy + dy]
      }
      @cx += dx
      @cy += dy
    end

    def curveto(dx1, dy1, dx2, dy2, dx3, dy3)
      @history << {
        :command => :curve,
        :s => [@cx, @cy],
        :b0 => [@cx + dx1, @cy + dy1],
        :b1 => [@cx + dx1 + dx2, @cy + dy1 + dy2],
        :e => [@cx + dx1 + dx2 + dx3, @cy + dy1 + dy2 + dy3]
      }
      @cx += dx1 + dx2 + dx3
      @cy += dy1 + dy2 + dy3
    end

    def closepath(to)
      if to then
        @history << {
          :command => :line,
          :s => [@cx, @cy],
          :e => to
        }
      end
    end
  end

  # Check Me!
  # source: http://partners.adobe.com/public/developer/en/ps/PLRM.pdf
  #         Appendix A
  @@standard_strings = %w/
    .notdef space exclam quotedbl numbersign dollar percent ampersand quoteright parenleft
    parenright asterisk plus comma hyphen period slash zero one two
    three four five six seven eight nine colon semicolon less
    equal greater question at A B C D E F
    G H I J K L M N O P
    Q R S T U V W X Y Z
    bracketleft backslash bracketright asciicircum underscore quoteleft a b c d
    e f g h i j k l m n
    o p q r s t u v w x
    y z braceleft bar braceright asciitilde exclamdown cent sterling fraction
    yen florin section currency quotesingle quotedblleft guillemotleft guilsinglleft guilsinglright fi
    fl endash dagger daggerdbl periodcentered paragraph bullet quotesinglbase quotedblbase quotedblright
    guillemotright ellipsis perthousand questiondown grave acute circumflex tilde macron breve
    dotaccent dieresis ring cedilla hungarumlaut ogonek caron emdash AE ordfeminine
    Lshash Oshash OE ordmasculine ae dotlessi lshash oslash oe germandbls
    onesuperior logicalnot mu trademark Eth onehalf plusminus Thorn onequarter divide
    brokenbar degree thown threequarters twosuperior registered minus eth multiply threesuperior
    copyright Aacute Acircumflex Adieresis Agrave Aring Atilde Ccedilla Eacute Ecircumflex
    Edieresis Egrave Iacute Icircumflex Idieresis Igrave Ntilde Oacute Ocircumflex Odieresis
    Ograve Otilde Scaron Uacute Ucircumflex Udieresis Ugrave Yacute Ydieresis Zcaron
    aacute acircumflex adieresis agrave aring atilde ccedilla eacute ecircumflex edieresis
    egrave iacute icircumflex idieresis igrave ntilde oacute ocircumflex odieresis ograve
    otilde scaron uacute ucircumflex udieresis ugrave yacute ydieresis zcaron exclamsmall
    Hungarumlautsmall dollaroldstyle dollarsuperior ampersandsmall Acutesmall parenleftsuperior parenrightsuperior twodotenleader onedotenleader zerooldstyle
    oneoldstyle twooldstyle threeoldstyle fouroldstyle fiveoldstyle sixoldstyle sevenoldstyle eightoldstyle nineoldstyle commasuperior
    threequartersemdash periodsuperior questionsmall asuperior bsuperior centsuperior dsuperior esuperior isuperior lsuperior
    msuperior nsuperior osuperior rsperior ssperior tsuperior ff ffi ffl parenleftinferior
    parenrightinferior Circumflexsmall hyphensuperior Gravesmall Asmall Bsmall Csmall Dsmall Esmall Fsmall
    Gsmall Hsmall Ismall Jsmall Ksmall Lsmall Msmall Nsmall Osmall Psmall
    Qsmall Rsmall Ssmall Tsmall Usmall Vsmall Wsmall Xsmall Ysmall Zsmall
    colonmonetary onefitted rupiah Tildesmall exclamdownsmall centoldstyle Lslashsmall Scaronsmall Zcaronsmall Dieresissmall
    Brevesmall Caronsmall Dotaccentsmall Macronsmall figuredash hypheninferior Ogoneksmall Ringsmall Cedillasmall questiondownsmall
    oneeighth threeeighths fiveeighths seveneighths onethird twothirds zerosuperior forsuperior fivesuperior sixsuperior
    sevensuperior eightsuperior ninesuperior zeroinferior oneinferior twoinferior threeinferior fourinferior fiveinferior sixinferior
    seveninferior eightinferior nineinferior centinferior dollarinferior periodinferior commainferior Agravesmall Aacutesmall Acircumflexsmall
    Atildesmall Adieresissmall Aringsmall AEsmall Ccedillasmall Egravesmall Eacutesmall Ecircumflexsmall Edieresissmall Igravesmall
    Iacutesmall Icircumflexsmall Idieresissmall Ethsmall Ntildesmall Ogravesmall Oacutesmall Ocircumflexsmall Otildesmall Odieresissmall
    OEsmall Oslashsmall Ugravesmall Uacutesmall Ucircumflexsmall Udieresissmall Yacutesmall Thornsmall Ydieresissmall 001.000
    001.001 001.002 001.003 Black Bold Book Light Medium Regular Roman
    Semibold
  /.freeze

  def seek_file
    loop do
      ch = @source.read 1
      if ch.ord == 'S'.ord then
        s = @source.read 'tartData '.length
        return if s =~ /^tartData/
      end
    end
  end

  def read_header
    major = read_Card8
    minor = read_Card8
    hdrSize = read_Card8
    offSize = read_OffSize
    raise 'CFF-Data with version != 1' if major != 1
    raise 'CFF-Data with Header-Size != 4' if hdrSize != 4
    return {
      :major => major,
      :minor => minor,
      :hdrSize => hdrSize,
      :offSize => offSize
    }
  end

  def read_charsets(length)
    format = read_Card8
    charsets = [0]
    case format
      when 0
        for i in 1 ... length do
          charsets[i] = read_SID
        end
      when 1
        cover_count = 0
        while cover_count < length do
          first = read_SID
          nLeft = read_Card8
          charsets.concat first .. first + nLeft
          cover_count += 1 + nLeft
        end
      when 2
        cover_count = 0
        while cover_count < length do
          first = read_SID
          nLeft = read_Card16
          charsets.concat first .. first + nLeft
          cover_count += 1 + nLeft
        end
    end
    return charsets
  end

  def read_byte
    return @source.read(1).ord
  end

  def read_Card8
    return read_byte
  end

  def read_Card16
    b0 = read_byte
    b1 = read_byte
    return b0 * 256 + b1
  end

  def read_OffSize
    return read_byte
  end

  def read_Offset(size)
    offset = 0
    for i in 1 .. size do
      offset = offset * 256 + read_byte
    end
    return offset
  end

  def read_SID
    b0 = read_byte
    b1 = read_byte
    return b0 * 256 + b1
  end

  def read_nibbles
    b = read_byte
    return [b >> 4 & 15, b & 15]
  end

  def read_INDEX
    count = read_Card16
    return [] if count == 0
    offSize = read_OffSize
    offsets = []
    for i in 0 .. count do
      offsets << read_Offset(offSize)
    end
    indexes = []
    for i in 0 ... count do
      size = offsets[i + 1] - offsets[i]
      indexes << @source.read(size)
    end
    return indexes
  end

  def parse(stream)
    ret = []
    while not stream.empty? do
      v = stream.shift
      case v
        when 1
          ret << :hstem
        when 3
          ret << :vstem
        when 4
          ret << :vmoveto
        when 5
          ret << :rlineto
        when 6
          ret << :hlineto
        when 7
          ret << :vlineto
        when 8
          ret << :rrcurveto
        when 10
          ret << :callsubr
        when 11
          ret << :return
        when 12
          case stream.shift
            when 3
              ret << :and
            when 4
              ret << :or
            when 5
              ret << :not
            when 9
              ret << :abs
            when 10
              ret << :add
            when 11
              ret << :sub
            when 12
              ret << :div
            when 14
              ret << :neg
            when 15
              ret << :eq
            when 18
              ret << :drop
            when 20
              ret << :put
            when 21
              ret << :get
            when 22
              ret << :ifelse
            when 23
              ret << :random
            when 24
              ret << :mul
            when 26
              ret << :sqrt
            when 27
              ret << :dup
            when 28
              ret << :exch
            when 29
              ret << :index
            when 30
              ret << :roll
            when 34
              ret << :hflex
            when 35
              ret << :flex
            when 36
              ret << :hflex1
            when 37
              ret << :flex1
            else
              raise 'reserved operator detected.'
          end
        when 14
          ret << :endchar
        when 18
          ret << :hstemhm
        when 19
          ret << :hintmask
        when 20
          ret << :cntrmask
        when 21
          ret << :rmoveto
        when 22
          ret << :hmoveto
        when 23
          ret << :vstemhm
        when 24
          ret << :rcurveline
        when 25
          ret << :rlinecurve
        when 26
          ret << :vvcurveto
        when 27
          ret << :hhcurveto
        when 28
          t = stream.shift 2
          ret << t[0] * 256 + t[1]
        when 29
          ret << :callgsubr
        when 30
          ret << :vhcurveto
        when 31
          ret << :hvcurveto
        when 32 .. 246
          ret << v - 139
        when 247 .. 250
          w = stream.shift
          ret << (v - 247) * 256 + w + 108
        when 251 .. 254
          w = stream.shift
          ret << -(v - 251) * 256 - w - 108
        when 255
          t = stream.shift 4
          ret << t[0] * 256 + t[1] + (t[2] * 256 + t[3]) / 65536.0
        else
          raise "reserved operator detected."
      end
    end
    return ret
  end

end

main
