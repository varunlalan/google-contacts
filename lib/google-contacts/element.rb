require 'net/http'

module GContacts
  class Element
    attr_accessor :addresses, :birthday, :content, :data, :category, :emails,
      :etag, :groups, :group_id, :hashed_addresses, :hashed_email_addresses,
      :hashed_phone_numbers, :hashed_mobile_numbers, :hashed_websites, :mobiles,
      :name, :organization, :org_name, :org_title, :phones, :title, :websites
    attr_reader :batch, :edit_uri, :id, :modifier_flag, :photo_uri, :updated

    ##
    # Creates a new element by parsing the returned entry from Google
    # @param [Hash, Optional] entry Hash representation of the XML returned from Google
    #
    def initialize(entry=nil)
      @data = {}
      return unless entry

      @id, @updated, @content, @title, @etag, @name = entry["id"], entry["updated"], entry["content"], entry["title"], entry["@gd:etag"], entry["gd:name"]
      @organization = entry['gd:organization']

      @photo_uri = nil
      if entry["category"]
        @category = entry["category"]["@term"].split("#", 2).last
        @category_tag = entry["category"]["@label"] if entry["category"]["@label"]
      end

      # Parse out all the relevant data
      entry.each do |key, unparsed|
        if key =~ /^(gd:|gContact:)/
          if unparsed.is_a?(Array)
            @data[key] = unparsed.map {|v| parse_element(v)}
          else
            @data[key] = [parse_element(unparsed)]
          end
        elsif key =~ /^batch:(.+)/
          @batch ||= {}

          if $1 == "interrupted"
            @batch["status"] = "interrupted"
            @batch["code"] = "400"
            @batch["reason"] = unparsed["@reason"]
            @batch["status"] = {"parsed" => unparsed["@parsed"].to_i, "success" => unparsed["@success"].to_i, "error" => unparsed["@error"].to_i, "unprocessed" => unparsed["@unprocessed"].to_i}
          elsif $1 == "id"
            @batch["status"] = unparsed
          elsif $1 == "status"
            if unparsed.is_a?(Hash)
              @batch["code"] = unparsed["@code"]
              @batch["reason"] = unparsed["@reason"]
            else
              @batch["code"] = unparsed.attributes["code"]
              @batch["reason"] = unparsed.attributes["reason"]
            end

          elsif $1 == "operation"
            @batch["operation"] = unparsed["@type"]
          end
        end
      end

      @groups = []
      if (groups = [entry["gContact:groupMembershipInfo"]])
        groups.flatten.compact.each do |group|
          @modifier_flag = :delete if group["@deleted"] == "true"
          @groups << { group_id: group["@href"].split('/').pop, group_href: group["@href"] }
        end
      end

      # Need to know where to send the update request
      if entry["link"].is_a?(Array)
        entry["link"].each do |link|
          if link["@rel"] == "edit"
            @edit_uri = URI(link["@href"])
          elsif (link["@rel"].match(/rel#photo$/) && link["@gd:etag"] != nil)
            @photo_uri = URI(link["@href"])
          end
        end
      end

      @emails = []
      if entry["gd:email"].is_a?(Array)
        nodes = entry["gd:email"]
      elsif !entry["gd:email"].nil?
        nodes = [entry["gd:email"]]
      else
        nodes = []
      end

      nodes.each do |email|
        new_email = {}
        new_email['address'] = email['@address']
        unless email['@rel'].nil?
          new_email['type'] = email['@rel']
        else
          new_email['type'] = email['@label']
        end

        @emails << new_email
      end

      @phones = []
      @mobiles = []
      if entry["gd:phoneNumber"].is_a?(Array)
        nodes = entry["gd:phoneNumber"]
      elsif !entry["gd:phoneNumber"].nil?
        nodes = [entry["gd:phoneNumber"]]
      else
        nodes = []
      end

      nodes.each do |phone|
        if phone.respond_to? :attributes
          new_phone = {}
          new_phone['text'] = phone
          google_category   = phone.attributes['rel'] || phone.attributes['label']
          new_phone['@rel'] = google_category
          if google_category.downcase.include?('mobile')
            @mobiles << new_phone
          else
            @phones << new_phone
          end
        end
      end

      @addresses = []
      if entry["gd:structuredPostalAddress"].is_a?(Array)
        nodes = entry["gd:structuredPostalAddress"]
      elsif !entry["gd:structuredPostalAddress"].nil?
        nodes = [entry["gd:structuredPostalAddress"]]
      else
        nodes = []
      end

      nodes.each do |address|
        new_address = {}
        new_address['gd:formattedAddress'] = address['gd:formattedAddress']
        unless address['@rel'].nil?
          new_address['type'] = address['@rel']
        else
          new_address['type'] = address['@label']
        end

        @addresses << new_address
      end

      @hashed_email_addresses = {}
      @emails.each do |email|
        type = email['type'].split("#").last
        text = email['address']
        @hashed_email_addresses.merge!(type => []) unless(@hashed_email_addresses[type])
        @hashed_email_addresses[type] << text
      end if @emails.any?

      @hashed_addresses = {}
      @addresses.each do |address|
        type = address['type'].split("#").last
        text = address['gd:formattedAddress']
        @hashed_addresses.merge!(type => []) unless(@hashed_addresses[type])
        @hashed_addresses[type] << text
      end if @addresses.any?

      @hashed_phone_numbers = {}
      @phones.each do |phone|
        type = phone['@rel'].split("#").last
        text = phone['text']
        @hashed_phone_numbers.merge!(type => []) unless(@hashed_phone_numbers[type])
        @hashed_phone_numbers[type] << text
      end if @phones.any?

      @hashed_mobile_numbers = {}
      @mobiles.each do |mobile|
        type = mobile['@rel'].split("#").last
        text = mobile['text']
        @hashed_mobile_numbers.merge!(type => []) unless(@hashed_mobile_numbers[type])
        @hashed_mobile_numbers[type] << text
      end

      @websites = []
      if entry["gContact:website"].is_a?(Array)
        nodes = entry["gContact:website"]
      elsif !entry["gContact:website"].nil?
        nodes = [entry["gContact:website"]]
      else
        nodes = []
      end

      nodes.each do |website|
        new_website = {}
        new_website['gContact:website'] = website['@href']
        new_website['type'] = website['@rel'].nil?  ? website['@label'] : website['@rel']
        @websites << new_website
      end

      organize_websites
      organize_birthdays(@data['gContact:birthday'])
      organization_details
    end

    ##
    # Converts the entry into XML to be sent to Google
    def to_xml(batch=false)
      xml = "<atom:entry xmlns:atom='http://www.w3.org/2005/Atom'"
      xml << " xmlns:gd='http://schemas.google.com/g/2005'"
      xml << " xmlns:gContact='http://schemas.google.com/contact/2008'"
      xml << " gd:etag='#{@etag}'" if @etag
      xml << ">\n"

      if batch
        xml << "  <batch:id>#{@modifier_flag}</batch:id>\n"
        xml << "  <batch:operation type='#{@modifier_flag == :create ? "insert" : @modifier_flag}'/>\n"
      end

      # While /base/ is whats returned, /full/ is what it seems to actually want
      if @id
        xml << "  <id>#{@id.to_s.gsub("/base/", "/full/")}</id>\n"
      end

      unless @modifier_flag == :delete
        xml << "  <atom:category scheme='http://schemas.google.com/g/2005#kind' term='http://schemas.google.com/g/2008##{@category}'/>\n"
        xml << "  <atom:content type='text'>#{CGI::escapeHTML(@content || '')}</atom:content>\n"
        xml << "  <atom:title>#{@title}</atom:title>\n"
        xml << "  <gContact:groupMembershipInfo deleted='false' href='#{@group_id}'/>\n" if @group_id

        @data.each do |key, parsed|
          xml << handle_data(key, parsed, 2)
        end
      end

      xml << "</atom:entry>\n"
    end

    ##
    # Flags the element for creation, must be passed through {GContacts::Client#batch} for the change to take affect.
    def create;
      unless @id
        @modifier_flag = :create
      end
    end

    ##
    # Flags the element for deletion, must be passed through {GContacts::Client#batch} for the change to take affect.
    def delete;
      if @id
        @modifier_flag = :delete
      else
        @modifier_flag = nil
      end
    end

    ##
    # Flags the element to be updated, must be passed through {GContacts::Client#batch} for the change to take affect.
    def update;
      if @id
        @modifier_flag = :update
      end
    end

    ##
    # Whether {#create}, {#delete} or {#update} have been called
    def has_modifier?; !!@modifier_flag end

    def inspect
      "#<#{self.class.name} title: \"#{@title}\", updated: \"#{@updated}\">"
    end

    alias to_s inspect


    # Update group list
    # usage : element.update_groups(list_of_group_ids)
    #
    def update_groups(*group_links)
      data.delete('gContact:groupMembershipInfo')
      group_links = group_links.flatten
      return if group_links.empty?

      data.merge!({ 'gContact:groupMembershipInfo' => [] })
      group_links.each do |group_link|
        params = { '@deleted' => 'false', '@href' => group_link.to_s }
        data['gContact:groupMembershipInfo'] << params
      end
    end

    private
     # Evil ahead
      def handle_data(tag, data, indent)
        if data.is_a?(Array)
          xml = ""
          data.each do |value|
            xml << write_tag(tag, value, indent)
          end
        else
          xml = write_tag(tag, data, indent)
        end

        xml
      end

      def organize_birthdays(primary_birthday)
        primary_birthday.blank? && return
        @birthday = primary_birthday.first['@when']
      end

      def organization_details
        @organization.blank? && return

        org_details = @organization.is_a?(Array) ?
          (@organization.select{ |k| k['@primary'] }.first || @organization.first) :
          @organization
        @org_name  = org_details['gd:orgName']
        @org_title = org_details['gd:orgTitle']
      end

      def organize_websites
        @hashed_websites = {}
        @websites.each do |website|
          href, type = website['gContact:website'], website['type']
          @hashed_websites.merge!(type => []) unless(@hashed_websites[type])
          @hashed_websites[type] << href
        end if @websites.any?
      end

      def parse_element(unparsed)
        data = {}

        if unparsed.is_a?(Hash)
          data = unparsed
        elsif unparsed.is_a?(Nori::StringWithAttributes)
          data["text"] = unparsed.to_s
          unparsed.attributes.each {|k, v| data["@#{k}"] = v}
        end

        data
      end

      def write_tag(tag, data, indent)
        data = CGI.escapeHTML(data)
        xml = " " * indent
        xml << "<" << tag

        # Need to check for any additional attributes to attach since they can be mixed in
        misc_keys = 0
        if data.is_a?(Hash)
          misc_keys = data.length

          data.each do |key, value|
            next unless key =~ /^@(.+)/
            xml << " #{$1}='#{value}'"
            misc_keys -= 1
          end

          # We explicitly converted the Nori::StringWithAttributes to a hash
          if data["text"] and misc_keys == 1
            data = data["text"]
          end

        # Nothing to filter out so we can just toss them on
        elsif data.is_a?(Nori::StringWithAttributes)
          data.attributes.each {|k, v| xml << " #{k}='#{v}'"}
        end

        # Just a string, can add it and exit quickly
        if !data.is_a?(Array) and !data.is_a?(Hash)
          xml << ">"
          xml << data.to_s
          xml << "</#{tag}>\n"
          return xml
        # No other data to show, was just attributes
        elsif misc_keys == 0
          xml << "/>\n"
          return xml
        end

        # Otherwise we have some recursion to do
        xml << ">\n"

        data.each do |key, value|
          next if key =~ /^@/
          xml << handle_data(key, value, indent + 2)
        end

        xml << " " * indent
        xml << "</#{tag}>\n"
      end
  end
end

