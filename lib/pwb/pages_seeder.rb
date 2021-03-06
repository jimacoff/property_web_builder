# To reload from console:
# load "#{Pwb::Engine.root}/lib/pwb/pages_seeder.rb"
# Pwb::PagesSeeder.seed_page_content_translations!
module Pwb
  class PagesSeeder
    class << self
      # Called by this rake task:
      # rake app:pwb:db:seed_pages                                  1 ↵
      def seed_page_parts!
        page_part_yml_filenames = [
          "about-us__our_agency.yml", "about-us__content_html.yml",
          "contact-us__form_and_map.yml", "contact-us__content_html.yml",
          "home__landing_hero.yml", "home__about_us_services.yml", "home__content_html.yml",
          "sell__content_html.yml",
          "privacy__content_html.yml", "legal__content_html.yml"
        ]

        page_part_yml_filenames.each do |filename|
          seed_page_part filename
        end
      end

      def seed_page_basics!
        page_yml_filenames = [
          "sell.yml", "about.yml", "buy.yml",
          "rent.yml", "home.yml", "legal_notice.yml",
          "contact.yml", "privacy_policy.yml"
        ]

        page_yml_filenames.each do |page_yml_filename|
          seed_page page_yml_filename
        end
      end

      # below need to have page_parts populated to work correctly
      def seed_page_content_translations!
        I18n.available_locales.each do |locale|
          seed_content_for_locale locale.to_s
        end
      end

      # def seed_rails_parts
      #   contact_us_page = Pwb::Page.find_by_slug "contact-us"
      #   contact_us_rails_part = contact_us_page.page_contents.find_or_create_by(label: "contact_us__form_and_map")
      # end

      protected


      def seed_page yml_file
        page_seed_file = Pwb::Engine.root.join('db', 'yml_seeds', 'pages', yml_file)
        page_yml = YAML.load_file(page_seed_file)
        unless Pwb::Page.where(slug: page_yml[0]['slug']).count > 0
          Pwb::Page.create!(page_yml)
        end
      end


      def seed_page_part yml_file
        lf_seed_file = Pwb::Engine.root.join('db', 'yml_seeds', 'page_parts', yml_file)
        lf_yml = YAML.load_file(lf_seed_file)
        unless Pwb::PagePart.where({page_part_key: lf_yml[0]['page_part_key'],page_slug: lf_yml[0]['page_slug']}).count > 0
          Pwb::PagePart.create!(lf_yml)
        end
      end

      def seed_content_for_locale locale
        locale_seed_file = Pwb::Engine.root.join('db', 'yml_seeds', 'content_translations', locale + '.yml')
        unless File.exist? locale_seed_file
          return
        end
        yml = YAML.load_file(locale_seed_file)

        Pwb::Page.all.each do |page|
          page.page_parts.each do |page_part|
            page_part_key = page_part.page_part_key
            # Items in each locale seed file are nested as
            # page_slug/page_part_key and then the block labels
            unless yml[locale] && yml[locale][page.slug] && yml[locale][page.slug][page_part_key]
              if page_part.is_rails_part
                page_fragment_content = page.contents.find_or_create_by(page_part_key: page_part_key)
                page_content_join_model = page_fragment_content.page_contents.find_by_page_id page.id

                page_content_join_model.page_part_key = page_part_key
                page_content_join_model.is_rails_part = true
                page_content_join_model.save!

                return
              end
              # skip if there is no content to populate
              next
            end
            if yml[locale][page.slug][page_part_key]
              seed_content = yml[locale][page.slug][page_part_key]
              set_page_block_content locale, page_part, seed_content
              set_page_content_order_and_visibility locale, page_part, seed_content
            end
          end
        end

      end

      def set_page_content_order_and_visibility locale, page_part, seed_content

        page_part_editor_setup = page_part.editor_setup
        page = page_part.page
        # page_part_key uniquely identifies a fragment
        page_part_key = page_part.page_part_key

        sort_order = page_part_editor_setup["default_sort_order"] || 1
        page.set_fragment_sort_order page_part_key, sort_order

        visible_on_page = false
        if page_part_editor_setup["default_visible_on_page"]
          visible_on_page = true
        end
        page.set_fragment_visibility page_part_key, visible_on_page
      end

      def set_page_block_content locale, page_part, seed_content

        page_part_editor_setup = page_part.editor_setup
        page = page_part.page
        # page_part_key uniquely identifies a fragment
        page_part_key = page_part.page_part_key

        # container for json to be attached to page details
        locale_block_content_json = {"blocks" => {}}
        # {"blocks"=>{"title_a"=>{"content"=>"about our agency"}, "content_a"=>{"content"=>""}}}
        page_part_editor_setup["editorBlocks"].each do |configColBlocks|
          configColBlocks.each do |configRowBlock|
            row_block_label = configRowBlock["label"]
            row_block_content = ""
            # find the content for current block from within the seed content
            if seed_content[row_block_label]
              if configRowBlock["isImage"]
                photo = page.seed_fragment_photo page_part_key, row_block_label, seed_content[row_block_label]
                if photo.present? && photo.optimized_image_url.present?
                  # optimized_image_url is defined in content_photo and will
                  # return cloudinary url or filesystem url depending on settings
                  row_block_content = photo.optimized_image_url
                else
                  row_block_content = "http://via.placeholder.com/350x250"
                end
              else
                row_block_content = seed_content[row_block_label]
              end
            end
            locale_block_content_json["blocks"][row_block_label] = {"content"=>row_block_content}
          end
        end

        # save the block contents (in associated page_part model)
        updated_details = page.set_page_part_block_contents page_part_key, locale, locale_block_content_json
        # retrieve the contents saved above and use to rebuild html for that page_part
        # (and save it in associated page_content model)
        fragment_html = page.rebuild_page_content page_part_key, locale

        p "#{page.slug} page #{page_part_key} content set for #{locale}."
      end

    end
  end
end
