require 'thor'
require 'nokogiri'
require 'yaml'
require 'csv'
require 'byebug'

class FormatMetadata < Thor
  DEFAULT_MAPPING = "default-mapping.yml"

  desc "Transform DRC metadata for Scholar",
       "Fills out a draft of the Scholar@UC batch update metadata profile"

  option :mapping

  def format(path)
    if options[:mapping].nil? 
      mapping_file = File.open DEFAULT_MAPPING 
    else
      mapping_file = File.open options[:mapping]
    end

    mapping = YAML.load mapping_file
    directories = Directories.new(path).directories

    meta_data_headers = mapping.keys
    csv_name = path + ".tab"
    CSV.open(csv_name, "wb", col_sep: "\t") do |csv|
      csv << meta_data_headers + Files.headers
      directories.each do |dir|
        metadata = Metadata.new(dir, mapping)
        files = Files.new(dir)
        csv << meta_data_headers.collect { |key| metadata.formatted_field(key) } + files.format_files
      end
    end
  end
end

class Directories
  attr_reader :directories, :path

  def initialize(path)
    @path = path
    @directories = add_pwd(get_directories(path))
  end

  private

  def add_pwd(directories)
    Dir.chdir(path)
    directories.map { |dir| File.join(Dir.pwd, dir) }
  end

  def get_directories(path)
    Dir.chdir(path) do
      Dir.glob('*').select { |f| File.directory? f }
    end
  end
end

class Metadata
  attr_reader :document, :mapping, :elements, :path

  def initialize(dir, mapping)
    @path = File.join(dir, "dublin_core.xml")
    @document = File.open(path) { |f| Nokogiri::XML(f) }
    @mapping = mapping
    @elements = set_elements
  end

  def formatted_field(key)
    return nil if elements[key].nil?
    elements[key].join("|").gsub(/\n/, "|")
  end

  private

  def set_elements
    h = {}
    mapping.each do |field, definition|
      h[field] = document.xpath(
        xpath_search_builder(definition)
      ).collect { |field| field.text }
    end
    h
  end

  def xpath_search_builder(definition)
    definition["qualifiers"].collect do |q|
      "//dcvalue[@element='#{definition["element"]}']" + "[@qualifier='#{q}']"
    end.join(" | ")
  end
end

class Files
  attr_reader :files, :contents_file, :path, :local_path

  def initialize(dir)
    @path = dir
    @local_path = File.join path.split("/")[-2..-1]
    @contents_file = File.readlines(File.join(path, "contents"))
    @files = []
    @files += add_original_files
    @files += add_archival_files
    @files += add_license_files
  end

  def format_files
    temp = []
    @files.each do |file|
      temp << file[:path]       #file_path
      temp << file[:title]      #file_title
      temp << file[:visibility] #file_visibility
      temp << nil               #file_embargo_release
      temp << nil               #file_uri
      temp << nil               #file_pid
    end
    temp
  end

  def self.headers
    %w{ file_path file_title file_visibility
    file_embargo_release file_uri file_pid }
  end

  private

  def add_original_files
    temp = []
    contents_file.grep(/bundle:ORIGINAL/).each do |line|
      temp_line = line.chomp.split("\t")
      temp_title = temp_line[2].nil? ? nil : temp_line[2].gsub(/description:/, "")
      temp << {
        path: local_path + temp_line[0],
        title: temp_title,
        visibility: nil
      }
    end
    temp
  end

  def add_archival_files
    temp = []
    contents_file.grep(/bundle:ARCHIVAL/).each do |line|
      temp_line = line.split("\t")
      temp_title = temp_line[2].nil? ? nil : temp_line[2].gsub(/description:/, "")
      temp << {
        path: local_path + temp_line[0],
        title: temp_title,
        visibility: "restricted"
      }
    end
    temp
  end

  def add_license_files
    temp = []
    contents_file.grep(/bundle:LICENSE/).each do |line|
      temp_line = line.split("\t")
      temp << {
        path: local_path + temp_line[0],
        title: nil,
        visibility: "restricted"
      }
    end
    temp
  end
end

FormatMetadata.start(ARGV)
