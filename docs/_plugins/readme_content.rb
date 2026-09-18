# frozen_string_literal: true

module C3pmDocs
  SECTIONS = {
    "Quick start" => "quick-start",
    "Command overview" => "commands",
    "Toolchain" => "toolchain",
    "C3 dependencies" => "c3-dependencies",
    "Linking libraries and projects" => "linking-libraries-and-projects",
    "Synchronize the project" => "synchronize-the-project",
    "Development shell" => "development-shell",
    "Portable bundles" => "portable-bundles",
    "Installer reference" => "installer-reference",
    "Project and library files" => "project-and-library-files",
    "Lock file" => "lock-file",
    "c3pm metadata reference" => "c3pm-metadata-reference",
    "How portable bundles work" => "how-portable-bundles-work",
    "Build c3pm from source" => "build-from-source",
    "License" => "license"
  }.freeze

  class ReadmeSections < Jekyll::Generator
    priority :high

    def generate(site)
      readme_path = File.expand_path("../README.md", site.source)
      readme = File.read(readme_path, encoding: "UTF-8")
      readme.sub!(/\A# .+\n+/, "")

      chunks = readme.split(/(?=^## )/)
      chunks.shift
      parsed_sections = chunks.filter_map do |chunk|
        match = chunk.match(/\A## (.+)\n/)
        next unless match

        title = match[1]
        slug = SECTIONS[title]
        next unless slug

        content = chunk.sub(/\A## .+\n+/, "")
        content.sub!("### 1. Install c3pm", "### 1. Install c3pm {#install}") if title == "Quick start"
        content.gsub!("[LICENSE](LICENSE)", "[LICENSE](https://github.com/SMFloris/c3pm/blob/main/LICENSE)")

        { title: title, slug: slug, content: content }
      end

      sections = parsed_sections.each_with_index.map do |section, index|
        previous = index.zero? ? { title: "Home", slug: "overview" } : parsed_sections[index - 1]
        following = parsed_sections[index + 1]

        <<~HTML
          <section class="doc-section" id="#{section[:slug]}" data-section="#{section[:slug]}" aria-hidden="true" markdown="1">
          <h2>#{section[:title]}</h2>

          #{section[:content]}

          <nav class="section-pagination" aria-label="Section navigation">
            #{pagination_link("previous", previous)}
            #{pagination_link("next", following)}
          </nav>
          </section>
        HTML
      end

      home = site.pages.find { |page| page.path == "index.md" }
      home.content = home.content.sub("<!-- README_SECTIONS -->", sections.join("\n"))
    end

    private

    def pagination_link(direction, section)
      return "" unless section

      label = direction == "previous" ? "Previous" : "Next"
      <<~HTML.strip
        <a class="section-page #{direction}" href="##{section[:slug]}">
          <span>#{label}</span>
          <strong>#{section[:title]}</strong>
        </a>
      HTML
    end
  end
end
