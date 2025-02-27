# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'pdf-reader'

module Jekyll
  class PdfPreprocessor < Generator
    safe true
    priority :highest

    def generate(site)
      @site = site
      # Rimuovere solo i PDF esistenti invece di tutti i file statici
      @site.static_files.reject! { |f| f.path.end_with?('.pdf') }
      clean_pdf_files("acquaalta")
      update_site_static_files
    end

    private

    def clean_pdf_files(directory)
      Dir.glob("#{directory}/**/*.pdf").each do |pdf_path|
        next if pdf_path.include?("/_site/") || pdf_path.include?("/._")

        dir = File.dirname(pdf_path)
        basename = File.basename(pdf_path, '.pdf')

        new_basename = basename.downcase
                             .gsub(/\./, '-')
                             .gsub(/[^a-z0-9\-]/, '-')
                             .gsub(/-+/, '-')
                             .gsub(/^-|-$/, '')

        new_path = File.join(dir, "#{new_basename}.pdf")

        unless pdf_path == new_path
          begin
            Jekyll.logger.info "PDF Preprocessor:", "Rinomino #{pdf_path} in #{new_path}"
            FileUtils.mv(pdf_path, new_path)
          rescue => e
            Jekyll.logger.error "PDF Preprocessor:", "Impossibile rinominare #{pdf_path}: #{e.message}"
          end
        end
      end
    end

    def update_site_static_files
      Dir.glob("acquaalta/**/*.pdf").each do |pdf_path|
        next if pdf_path.include?("/_site/") || pdf_path.include?("/._")

        rel_dir = File.dirname(pdf_path).sub(@site.source + '/', '')
        @site.static_files << StaticFile.new(
          @site,
          @site.source,
          rel_dir,
          File.basename(pdf_path)
        )
      end
    end
  end

  class PdfHandler < Generator
    safe true
    priority :high

    def generate(site)
      @site = site
      process_pdfs
    end

    private

    def process_pdfs
      Dir.glob("acquaalta/**/*.pdf").each do |pdf_path|
        next if pdf_path.include?("/_site/") || pdf_path.include?("/._")

        md_path = pdf_path.sub(/\.pdf$/, '.md')
        next if File.exist?(md_path)

        create_markdown_file(pdf_path, md_path)
      end
    end

    def create_markdown_file(pdf_path, md_path)
      reader = PDF::Reader.new(pdf_path)
      info = reader.info

      title = info[:Title] || File.basename(pdf_path, '.pdf')
      authors = info[:Author] ? [{'surname' => info[:Author]}] : [{'surname' => 'Cognome'}]
      year = info[:CreationDate] ? Date.parse(info[:CreationDate]).year.to_s : Time.now.year.to_s

      frontmatter = {
        'layout' => 'document',
        'title' => title,
        'authors' => authors,
        'date' => year,
        'category' => '',
        'tags' => [],
        'pdf_path' => "/#{pdf_path}",
        'parent' => 'Biblioteca'
      }

      File.open(md_path, 'w') do |file|
        file.puts frontmatter.to_yaml
        file.puts "---\n"
      end
    end

    def parse_filename(filename)
      parts = filename.split('-')

      if parts[0].match?(/^\d{4}$/)
        year = parts[0].to_i
        authors = parts[1]
        title = parts[2..-1].join(' ')
        [year, authors, title]
      else
        [nil, nil, filename]
      end
    end
  end

  class MarkdownWatcher < Generator
    safe true
    priority :low

    def generate(site)
      @site = site
      watch_markdown_files
    end

    private

    def watch_markdown_files
      Dir.glob("acquaalta/**/*.md").each do |md_path|
        next unless File.exist?(md_path)
        next if md_path.include?("/_site/")

        begin
          content = File.read(md_path)
          frontmatter = extract_frontmatter(content)
          next unless frontmatter

          migrate_authors_format(frontmatter) if frontmatter['author']

          update_filename(md_path, frontmatter)
        rescue => e
          Jekyll.logger.warn "PDF Handler:", "Errore nel processare #{md_path}: #{e.message}"
        end
      end
    end

    def extract_frontmatter(content)
      if content =~ /\A(---\s*\n.*?\n?)^(---\s*$\n?)/m
        YAML.safe_load($1, permitted_classes: [Time, Date])
      end
    end

    def migrate_authors_format(frontmatter)
      if frontmatter['author']
        frontmatter['authors'] = [{'surname' => frontmatter['author']['surname']}]
        frontmatter.delete('author')
      end
    end

    def update_filename(md_path, frontmatter)
      return unless frontmatter['authors'] && frontmatter['title']

      dir = File.dirname(md_path)
      date = frontmatter['date'].to_s

      authors_string = frontmatter['authors']
        .map { |author| author['surname'].downcase }
        .join('-')
        .gsub(/[^a-z0-9\-]/, '-')
        .gsub(/-+/, '-')
        .gsub(/^-|-$/, '')

      title = frontmatter['title'].downcase
                                 .gsub(/[^a-z0-9\-]/, '-')
                                 .gsub(/-+/, '-')
                                 .gsub(/^-|-$/, '')

      new_md_name = "#{date}-#{authors_string}-#{title}.md"
      new_pdf_name = "#{date}-#{authors_string}-#{title}.pdf"

      new_md_path = File.join(dir, new_md_name)
      new_pdf_path = File.join(dir, new_pdf_name)

      return if File.identical?(md_path, new_md_path)

      pdf_path = md_path.sub(/\.md$/, '.pdf')

      if File.exist?(pdf_path) && !File.identical?(pdf_path, new_pdf_path)
        begin
          FileUtils.mv(pdf_path, new_pdf_path)
          frontmatter['pdf_path'] = "/#{new_pdf_path}"
        rescue => e
          Jekyll.logger.warn "PDF Handler:", "Impossibile spostare #{pdf_path} a #{new_pdf_path}: #{e.message}"
          return
        end
      end

      File.open(md_path, 'w') do |file|
        file.puts frontmatter.to_yaml
        file.puts "---\n"
      end

      begin
        FileUtils.mv(md_path, new_md_path) unless File.identical?(md_path, new_md_path)
      rescue => e
        Jekyll.logger.warn "PDF Handler:", "Impossibile spostare #{md_path} a #{new_md_path}: #{e.message}"
      end
    end
  end
end
