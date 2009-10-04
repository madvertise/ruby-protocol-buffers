require 'protobuf/compiler/descriptor.pb'
require 'stringio'

class FileDescriptorToRuby < Struct.new(:descriptor)

  include FieldDescriptorProto::Type
  include FieldDescriptorProto::Label

  def initialize(descriptor)
    super
    @package = capfirst(descriptor.package_)
    @ns = []
  end

  def write(io)
    @io = io

    @io.write <<HEADER
#!/usr/bin/env ruby
# Generated by the protocol buffer compiler. DO NOT EDIT!

require 'protobuf/message/message'

HEADER
    descriptor.dependency.each do |dep|
      path = File.basename(dep, ".proto") + ".pb"
      @io.write("begin; require '#{path}'; rescue LoadError; end\n")
    end
    @io.write("\n") unless descriptor.dependency.empty?

    # in_namespace correctly handles the case where @package.nil?
    in_namespace("module", @package) do
      declare(descriptor.message_type, descriptor.enum_type)

      descriptor.message_type.each do |message|
        dump_message(message)
      end

      descriptor.enum_type.each do |enum|
        dump_enum(enum)
      end
    end

  end

  protected

  def declare(messages, enums)
    return if messages.empty? && enums.empty?

    line %{# forward declarations}
    messages.each do |message|
      # TODO: this is wrong
      line %{class #{name([@package, message.name])} < ::Protobuf::Message; end}
    end
    enums.each do |enum|
      line %{module #{name([@package, enum.name])}; end}
    end
    line
  end

  def line(str = nil)
    if str
      @ns.size.times { @io.write("  ") }
      @io.write(str)
    end
    @io.write("\n")
  end

  def in_namespace(type, name, rest = "")
    if !name || name == ""
      yield
    else
      line "#{type} #{capfirst(name)}#{rest}"
      @ns.push name
      yield
      @ns.pop
      line "end"
    end
  end

  def name(parts)
    ns = @ns.dup
    (parts.shift; ns.shift) while !parts.empty? && parts.first == ns.first
    parts.map { |p| capfirst(p) }.join("::")
  end

  LABEL_MAPPING = {
    LABEL_OPTIONAL => "optional",
    LABEL_REQUIRED => "required",
    LABEL_REPEATED => "repeated",
  }

  TYPE_MAPPING = {
    TYPE_DOUBLE => ":double",
    TYPE_FLOAT => ":float",
    TYPE_INT64 => ":int64",
    TYPE_UINT64 => ":uint64",
    TYPE_INT32 => ":int32",
    TYPE_FIXED64 => ":fixed64",
    TYPE_FIXED32 => ":fixed32",
    TYPE_BOOL => ":bool",
    TYPE_STRING => ":string",
    TYPE_BYTES => ":bytes",
    TYPE_UINT32 => ":uint32",
    TYPE_SFIXED32 => ":sfixed32",
    TYPE_SFIXED64 => ":sfixed64",
    TYPE_SINT32 => ":sint32",
    TYPE_SINT64 => ":sint64",
  }

  def dump_message(message)
    in_namespace("class", message.name, " < ::Protobuf::Message") do
      declare(message.nested_type, message.enum_type)

      line %{# nested messages} unless message.nested_type.empty?
      message.nested_type.each { |inner| dump_message(inner) }

      line %{# nested enums} unless message.enum_type.empty?
      message.enum_type.each { |inner| dump_enum(inner) }

      message.field.each do |field|
        typename = field_typename(field)
        fieldline = %{#{LABEL_MAPPING[field.label]} #{typename}, :#{field.name}, #{field.number}}
        if field.default_value && field.default_value != ""
          fieldline << %{, :default => #{default_value(field)}}
        end
        line fieldline
      end

      line
      line "gen_methods! # new fields ignored after this point"
    end
    line
  end

  def dump_enum(enum)
    in_namespace("module", enum.name) do
      line %{include ::Protobuf::Enum}
      enum.value.each do |value|
        line %{#{capfirst(value.name)} = #{value.number}}
      end
    end
    line
  end

  def field_typename(field)
    TYPE_MAPPING[field.type] || field.type_name.split(".").map { |t| capfirst(t) }.join("::")
  end

  # TODO: this probably doesn't work for all default values, expand
  def default_value(field)
    case field.type
    when TYPE_STRING, TYPE_BYTES
      %{"#{field.default_value}"}
    when TYPE_BOOL
      field.default_value
    when TYPE_ENUM
      typename = field_typename(field)
      %{#{typename}::#{field.default_value}}
    else
      field.default_value
    end
  end

  def capfirst(s)
    "#{s[0,1].capitalize}#{s[1..-1]}" if s
  end

  def output(line)
    @curfile.write("  " * @indent)
    @curfile.write(line)
    @curfile.write("\n")
  end

  def name_with_package(nm)
    if @package
      "#{capfirst(@package)}::#{nm}"
    else
      nm
    end
  end

end
