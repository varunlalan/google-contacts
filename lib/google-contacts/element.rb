require 'net/http'

REL = {
  '0' => "http://schemas.google.com/g/2005#work",   # Work
  '1' => "http://schemas.google.com/g/2005#home",   # Home
  '2' => "http://schemas.google.com/g/2005#other"   # Other
}

module GContacts
  class Element
    attr_accessor :title, :content, :data, :category, :etag, :group_id, :name, :emails, #:emails,
      :phones, :addresses#, :addresses, :phones
    attr_reader :id, :edit_uri, :modifier_flag, :updated, :batch, :photo_uri

    ##
    # Creates a new element by parsing the returned entry from Google
    # @param [Hash, Optional] entry Hash representation of the XML returned from Google
    #
    def initialize(entry=nil)
      @data = {}
      return unless entry

      @id, @updated, @content, @title, @etag, @name, @emails = entry["id"], entry["updated"], entry["content"], entry["title"], entry["@gd:etag"], entry["gd:name"], entry["gd:email"]
      # @address = entry["gd:structuredPostalAddress"]

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

      if entry["gContact:groupMembershipInfo"].is_a?(Hash)
        @modifier_flag = :delete if entry["gContact:groupMembershipInfo"]["@deleted"] == "true"
        @group_id = entry["gContact:groupMembershipInfo"]["@href"]
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

      @phones = []
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
          unless phone.attributes['rel'].nil?
            new_phone['@rel'] = phone.attributes['rel']
          else
            new_phone['type'] = phone.attributes['label']
          end
          @phones << new_phone
        end
      end

      # @emails = []
      # if entry["gd:email"].is_a?(Array)
      #   nodes = entry["gd:email"]
      # elsif !entry["gd:email"].nil?
      #   nodes = [entry["gd:email"]]
      # else
      #   nodes = []
      # end

      # nodes.each do |email|
      #   new_email = {}
      #   new_email['address'] = email['@address']
      #   unless email['@rel'].nil?
      #     new_email['type'] = email['@rel']
      #   else
      #     new_email['type'] = email['@label']
      #   end

      #   @emails << new_email
      # end

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
        xml << "  <updated>#{Time.now.utc.iso8601}</updated>\n"
        xml << "  <atom:content type='text'>#{@content}</atom:content>\n"
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

    ##
    # Using below methods instead of attr_accessor for updating details of a contact
    # NOTE: these methods will also create a new individual email, etc if not present
    #
    # Update addresses
    # Usage : element.update_address(array_of_addresses)
    # parameter is of the form [work, home, *others]
    # if paramater is left empty, it will remove all the addresses from a contact
    #
    def update_addresses(addresses = [])
      data.delete("gd:structuredPostalAddress")
      return unless addresses.any?

      data.merge!('gd:structuredPostalAddress' => [])
      addresses.each_with_index do |address, i|
        if ((i > 1) && (address))
          data['gd:structuredPostalAddress'] << {"@rel" => REL['2'], "gd:formattedAddress" => "#{address}" }
        elsif address
          data['gd:structuredPostalAddress'] << {"@rel" => REL["#{i}"], "gd:formattedAddress" => "#{address}" }
        end
      end
    end

    # Update email addresses
    # Usage : element.update_email(array_of_emails)
    # parameter is of the form [work, home, *others]
    # if paramater is left empty, it will remove all the emails from a contact
    #
    def update_emails(emails = [])
      data.delete("gd:email")
      return unless emails.any?

      data.merge!('gd:email' => [])
      emails.each_with_index do |email, i|
        if ((i > 1) && (email))
          data['gd:email'] << {"@rel" => REL['2'], "@address" => "#{email}" }
        elsif email
          data['gd:email'] << {"@rel" => REL["#{i}"], "@address" => "#{email}" }
        end
      end
      data['gd:email'].first.merge!("@primary"=>"true")
    end

    # Update phones
    # Usage : element.update_email(array_of_mobile, array_of_phones)
    # parameter(array_of_phones) is of the form [work, home, *others]
    # if paramater is left empty, it will remove all the mobiles/phones from a contact
    #
    def update_phones(mobiles = [], phones = [])
      data.delete("gd:phoneNumber")
      return unless (mobiles.any? && phones.any?)

      data.merge!('gd:phoneNumber' => [])
      # update mobile numbers
      mobiles.each do |mobile|
        data['gd:phoneNumber'] << {"@rel" => 'http://schemas.google.com/g/2005#mobile', "text" => "#{mobile}" } if mobile
      end if mobiles.any?
      # update phone numbers
      phones.each_with_index do |phone, i|
        if ((i > 1) && (phone))
          data['gd:phoneNumber'] << {"@rel" => REL['2'], "text" => "#{phone}" }
        elsif phone
          data['gd:phoneNumber'] << {"@rel" => REL["#{i}"], "text" => "#{phone}" }
        end
      end if phones.any?
    end

    # Update name
    # usage : element.update_name(full_name_of_a_contact)
    #
    def update_name(full_name)
      if data['gd:name']
        hash = data['gd:name'].first
        hash.select! {|k,v| ['gd:fullName'].include?(k)}
        hash['gd:fullName'] = "#{full_name}"
      else
        data.merge!("gd:name" => [{"gd:fullName" => "#{full_name}"}])
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

      def write_tag(tag, data, indent)
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
  end
end

