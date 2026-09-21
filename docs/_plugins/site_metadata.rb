# frozen_string_literal: true

module C3pmDocs
  class SiteMetadata < Jekyll::Generator
    priority :high

    def generate(site)
      version_path = File.expand_path("../src/version.c3", site.source)
      site.config["c3pm_version"] = required_match(
        File.read(version_path), /C3PM_VERSION\s*=\s*"([^"]+)"/, version_path
      )

      # The release workflow updates this version marker in the README.
      readme_path = File.expand_path("../README.md", site.source)
      site.config["c3_version"] = required_match(
        File.read(readme_path), /^> \*\*Default C3 target:\*\* C3 ([0-9A-Za-z.+-]+)\.$/, readme_path
      )

      navigation = site.data.fetch("navigation").flat_map do |group|
        group.fetch("items").map { |item| item.merge("group" => group.fetch("title")) }
      end
      urls = navigation.map { |item| item.fetch("url") }
      raise "Duplicate documentation navigation URL" unless urls.uniq == urls

      navigation.each_with_index do |item, index|
        pages = site.pages.select { |page| page.url == item.fetch("url") }
        raise "Expected one page for #{item.fetch('url')}, found #{pages.length}" unless pages.length == 1

        page = pages.first
        page.data["nav_group"] = item.fetch("group")
        page.data["previous_page"] = navigation[index - 1] unless index.zero?
        page.data["next_page"] = navigation[index + 1]
      end
    end

    private

    def required_match(content, pattern, path)
      match = content.match(pattern)
      raise "Could not find version in #{path}" unless match

      match[1]
    end
  end
end
