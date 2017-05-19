# -*- coding: utf-8 -*-
require 'redcarpet'
require 'coderay'
require 'nokogiri'
require "cgi"

class Dash < Struct.new(:source_dir, :output_dir, :out_dir)
  class << self
    def generate(source_dir, output_dir, out_dir)
      new(source_dir, output_dir, out_dir).generate
    end
  end

  def initialize(*)
    super
    self.output_dir = File.absolute_path(output_dir)
  end

  def generate
    puts "Output Dir: #{output_dir}"

    FileUtils.rm_r(docset_path) if Dir.exists? docset_path
    @contents_dir = "#{docset_path}/Contents"
    @resources_dir = "#{@contents_dir}/Resources"
    @documents_dir = "#{@resources_dir}/Documents"

    FileUtils.mkdir_p @documents_dir
    build_info_plist
    initialize_sqlite
    copy_assets output_dir, @documents_dir

    Dir.chdir output_dir do
      Dir.glob("#{output_dir}/*.html").each do|file_path|
        next if file_path =~ /release_notes.html\z/
        next if File.basename(file_path) =~ /\A_/
        doc_name = File.basename(file_path).sub(".md", "")

        File.open(file_path) do |file|
          html = create_html_and_register_index(file, doc_name)
          File.write("#{@documents_dir}/#{doc_name}", html)
        end
      end
    end
  end

  private

  def docset_path
    File.join(output_dir, out_dir)
  end

  def create_html_and_register_index(file, doc_name)
    html_body = file.read
    html_body.scan(/(<h[1-5]( [^>]+)?>(.*?)<\/h([1-5])>)/).each do |match|
      tag = match[0]
      name = ActionView::Base.full_sanitizer.sanitize(match[2])
      puts "Index: #{name}"
      hash = Digest::MD5.hexdigest name

      # Add Anchor to Header Tag
      html_body.sub!(tag, %{<a name="#{hash}"></a>#{tag}})

      # Add Search Index
      index_name = CGI.unescapeHTML(name).gsub("'"){ "''" }
      sqlite %{INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('#{index_name}', 'Guide', '#{doc_name}##{hash}');}
    end
    # relative
    html_body.gsub!('src="/images/', 'src="./images/')
    html_body.gsub!('href="/"', 'src="./index.html"')

    # Rremove Navigation and Header
    doc = Nokogiri::HTML.parse(html_body, nil, 'utf-8')
    doc.search("#topNav").remove
    doc.search("#header").remove
    doc.to_html
  end

  def copy_assets(source_dir, destination_dir)
    %w{images stylesheets}.each do |dir|
      src = "#{source_dir}/#{dir}"
      dst = "#{destination_dir}/#{dir}"
      FileUtils.rm_r dst if Dir.exists? dst
      FileUtils.cp_r src, dst
    end
  end

  def initialize_sqlite
    @sqlite_db = "#{@resources_dir}/docSet.dsidx"
    sqlite "DROP TABLE IF EXISTS searchIndex;"
    sqlite "CREATE TABLE IF NOT EXISTS searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);"
    sqlite "CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);"
  end

  def sqlite(query)
    `sqlite3  #{@sqlite_db} "#{query}"`
  end

  def build_info_plist
    File.write("#{@contents_dir}/Info.plist", <<-HTML)
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleIdentifier</key>
    <string>railsguidesjp</string>
    <key>CFBundleName</key>
    <string>Railsガイド</string>
    <key>DocSetPlatformFamily</key>
    <string>rails</string>
    <key>isDashDocset</key>
    <true/>
  </dict>
</plist>
    HTML
  end
end
