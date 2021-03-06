require 'banzai'
require 'html/pipeline/filter'

module Banzai
  module Filter
    # HTML Filter for parsing Gollum's tags in HTML. It's only parses the
    # following tags:
    #
    # - Link to internal pages:
    #
    #   * [[Bug Reports]]
    #   * [[How to Contribute|Contributing]]
    #
    # - Link to external resources:
    #
    #   * [[http://en.wikipedia.org/wiki/Git_(software)]]
    #   * [[Git|http://en.wikipedia.org/wiki/Git_(software)]]
    #
    # - Link internal images, the special attributes will be ignored:
    #
    #   * [[images/logo.png]]
    #   * [[images/logo.png|alt=Logo]]
    #
    # - Link external images, the special attributes will be ignored:
    #
    #   * [[http://example.com/images/logo.png]]
    #   * [[http://example.com/images/logo.png|alt=Logo]]
    #
    # - Insert a Table of Contents list:
    #
    #   * [[_TOC_]]
    #
    # Based on Gollum::Filter::Tags
    #
    # Context options:
    #   :project_wiki (required) - Current project wiki.
    #
    class GollumTagsFilter < HTML::Pipeline::Filter
      include ActionView::Helpers::TagHelper

      # Pattern to match tags content that should be parsed in HTML.
      #
      # Gollum's tags have been made to resemble the tags of other markups,
      # especially MediaWiki. The basic syntax is:
      #
      # [[tag]]
      #
      # Some tags will accept attributes which are separated by pipe
      # symbols.Some attributes must precede the tag and some must follow it:
      #
      # [[prefix-attribute|tag]]
      # [[tag|suffix-attribute]]
      #
      # See https://github.com/gollum/gollum/wiki
      #
      # Rubular: http://rubular.com/r/7dQnE5CUCH
      TAGS_PATTERN = %r{\[\[(.+?)\]\]}.freeze

      # Pattern to match allowed image extensions
      ALLOWED_IMAGE_EXTENSIONS = %r{.+(jpg|png|gif|svg|bmp)\z}i.freeze

      def call
        search_text_nodes(doc).each do |node|
          # A Gollum ToC tag is `[[_TOC_]]`, but due to MarkdownFilter running
          # before this one, it will be converted into `[[<em>TOC</em>]]`, so it
          # needs special-case handling
          if toc_tag?(node)
            process_toc_tag(node)
          else
            content = node.content

            next unless content =~ TAGS_PATTERN

            html = process_tag($1)

            if html && html != node.content
              node.replace(html)
            end
          end
        end

        doc
      end

      private

      # Replace an entire `[[<em>TOC</em>]]` node with the result generated by
      # TableOfContentsFilter
      def process_toc_tag(node)
        node.parent.parent.replace(result[:toc].presence || '')
      end

      # Process a single tag into its final HTML form.
      #
      # tag - The String tag contents (the stuff inside the double brackets).
      #
      # Returns the String HTML version of the tag.
      def process_tag(tag)
        parts = tag.split('|')

        return if parts.size.zero?

        process_image_tag(parts) || process_page_link_tag(parts)
      end

      # Attempt to process the tag as an image tag.
      #
      # tag - The String tag contents (the stuff inside the double brackets).
      #
      # Returns the String HTML if the tag is a valid image tag or nil
      # if it is not.
      def process_image_tag(parts)
        content = parts[0].strip

        return unless image?(content)

        if url?(content)
          path = content
        elsif file = project_wiki.find_file(content)
          path = ::File.join project_wiki_base_path, file.path
        end

        if path
          content_tag(:img, nil, src: path)
        end
      end

      def toc_tag?(node)
        node.content == 'TOC' &&
          node.parent.name == 'em' &&
          node.parent.parent.text == '[[TOC]]'
      end

      def image?(path)
        path =~ ALLOWED_IMAGE_EXTENSIONS
      end

      def url?(path)
        path.start_with?(*%w(http https))
      end

      # Attempt to process the tag as a page link tag.
      #
      # tag - The String tag contents (the stuff inside the double brackets).
      #
      # Returns the String HTML if the tag is a valid page link tag or nil
      # if it is not.
      def process_page_link_tag(parts)
        if parts.size == 1
          url = parts[0].strip
        else
          name, url = *parts.compact.map(&:strip)
        end

        content_tag(:a, name || url, href: url)
      end

      def project_wiki
        context[:project_wiki]
      end

      def project_wiki_base_path
        project_wiki && project_wiki.wiki_base_path
      end

      # Ensure that a :project_wiki key exists in context
      #
      # Note that while the key might exist, its value could be nil!
      def validate
        needs :project_wiki
      end
    end
  end
end
