require "spec_helper"

describe GContacts::Element do
  include Support::ResponseMock

  let(:parser) { Nori.new }

  it "changes modifier flags" do
    element = GContacts::Element.new

    element.create
    element.modifier_flag.should == :create

    element.delete
    element.modifier_flag.should == nil

    element.instance_variable_set(:@id, URI("http://google.com/a/b/c"))
    element.update
    element.modifier_flag.should == :update

    element.delete
    element.modifier_flag.should == :delete
  end

  context "converts back to xml" do
    before :each do
      Time.any_instance.stub(:iso8601).and_return("2012-04-06T06:02:04Z")
    end

    it "with batch used" do
      element = GContacts::Element.new

      element.create
      xml = element.to_xml(true)
      xml.should =~ %r{<batch:id>create</batch:id>}
      xml.should =~ %r{<batch:operation type='insert'/>}

      element.instance_variable_set(:@id, URI("http://google.com/a/b/c"))
      element.update

      xml = element.to_xml(true)
      xml.should =~ %r{<batch:id>update</batch:id>}
      xml.should =~ %r{<batch:operation type='update'/>}

      element.delete
      xml = element.to_xml(true)
      xml.should =~ %r{<batch:id>delete</batch:id>}
      xml.should =~ %r{<batch:operation type='delete'/>}
    end

    it "with deleting an entry" do
      element = GContacts::Element.new(parser.parse(File.read("spec/responses/contacts/get.xml"))["entry"])
      element.delete

      parser.parse(element.to_xml).should == {"atom:entry" => {"id"=>"http://www.google.com/m8/feeds/contacts/john.doe%40gmail.com/full/3a203c8da7ac0a8", "@xmlns:atom"=>"http://www.w3.org/2005/Atom", "@xmlns:gd"=>"http://schemas.google.com/g/2005", "@xmlns:gContact"=>"http://schemas.google.com/contact/2008", "@gd:etag"=>"\"YzllYTBkNmQwOWRlZGY1YWEyYWI5.\""}}
    end

    it "with creating an entry" do
      element = GContacts::Element.new
      element.category = "contact"
      element.content = "Foo Content"
      element.title = "Foo Title"
      element.data = {"gd:name" => {"gd:fullName" => "John Doe", "gd:givenName" => "John", "gd:familyName" => "Doe"}}
      element.create

      parser.parse(element.to_xml).should == {"atom:entry"=>{"atom:category"=>{"@scheme"=>"http://schemas.google.com/g/2005#kind", "@term"=>"http://schemas.google.com/g/2008#contact"}, "atom:content"=>"Foo Content", "atom:title"=>"Foo Title", "gd:name"=>{"gd:fullName"=>"John Doe", "gd:givenName"=>"John", "gd:familyName"=>"Doe"}, "@xmlns:atom"=>"http://www.w3.org/2005/Atom", "@xmlns:gd"=>"http://schemas.google.com/g/2005", "@xmlns:gContact"=>"http://schemas.google.com/contact/2008"}}
    end

    it "updating an entry" do
      element = GContacts::Element.new(parser.parse(File.read("spec/responses/contacts/get.xml"))["entry"])
      element.update

      parser.parse(element.to_xml).should == {"atom:entry"=>{"id"=>"http://www.google.com/m8/feeds/contacts/john.doe%40gmail.com/full/3a203c8da7ac0a8", "atom:category"=>{"@scheme"=>"http://schemas.google.com/g/2005#kind", "@term"=>"http://schemas.google.com/g/2008#contact"}, "atom:content"=>{"@type"=>"text"}, "atom:title"=>"Casey", "gd:name"=>{"gd:fullName"=>"Casey", "gd:givenName"=>"Casey"}, "gd:email"=>[{"@rel"=>"http://schemas.google.com/g/2005#work", "@address"=>"casey@gmail.com", "@primary"=>"true"}, {"@rel"=>"http://schemas.google.com/g/2005#home", "@address"=>"casey.1900@gmail.com"}, {"@rel"=>"http://schemas.google.com/g/2005#home", "@address"=>"casey_case@gmail.com"}], "gd:phoneNumber"=>["3005004000", "+130020003000"], "gd:structuredPostalAddress"=>[{"gd:formattedAddress"=>"Xolo\n      Dome\n      Krypton", "gd:street"=>"Xolo", "gd:city"=>"Dome", "gd:region"=>"Krypton", "@rel"=>"http://schemas.google.com/g/2005#home"}, {"gd:formattedAddress"=>"Nokia Lumia 720\n      Finland\n      Earth", "gd:street"=>"Nokia Limia 720", "gd:city"=>"Finland", "gd:region"=>"Earth", "@rel"=>"http://schemas.google.com/g/2005#work"}], "@xmlns:atom"=>"http://www.w3.org/2005/Atom", "@xmlns:gd"=>"http://schemas.google.com/g/2005", "@xmlns:gContact"=>"http://schemas.google.com/contact/2008", "@gd:etag"=>"\"YzllYTBkNmQwOWRlZGY1YWEyYWI5.\""}}
    end

    it "updating an entry serialized and deserialized" do
      element = GContacts::Element.new(parser.parse(File.read("spec/responses/contacts/get.xml"))["entry"])
      element = YAML::load(YAML::dump(element))
      element.update

      parser.parse(element.to_xml).should == {"atom:entry"=>{"id"=>"http://www.google.com/m8/feeds/contacts/john.doe%40gmail.com/full/3a203c8da7ac0a8", "atom:category"=>{"@scheme"=>"http://schemas.google.com/g/2005#kind", "@term"=>"http://schemas.google.com/g/2008#contact"}, "atom:content"=>{"@type"=>"text"}, "atom:title"=>"Casey", "gd:name"=>{"gd:fullName"=>"Casey", "gd:givenName"=>"Casey"}, "gd:email"=>[{"@rel"=>"http://schemas.google.com/g/2005#work", "@address"=>"casey@gmail.com", "@primary"=>"true"}, {"@rel"=>"http://schemas.google.com/g/2005#home", "@address"=>"casey.1900@gmail.com"}, {"@rel"=>"http://schemas.google.com/g/2005#home", "@address"=>"casey_case@gmail.com"}], "gd:phoneNumber"=>["3005004000", "+130020003000"], "gd:structuredPostalAddress"=>[{"gd:formattedAddress"=>"Xolo\n      Dome\n      Krypton", "gd:street"=>"Xolo", "gd:city"=>"Dome", "gd:region"=>"Krypton", "@rel"=>"http://schemas.google.com/g/2005#home"}, {"gd:formattedAddress"=>"Nokia Lumia 720\n      Finland\n      Earth", "gd:street"=>"Nokia Limia 720", "gd:city"=>"Finland", "gd:region"=>"Earth", "@rel"=>"http://schemas.google.com/g/2005#work"}], "@xmlns:atom"=>"http://www.w3.org/2005/Atom", "@xmlns:gd"=>"http://schemas.google.com/g/2005", "@xmlns:gContact"=>"http://schemas.google.com/contact/2008", "@gd:etag"=>"\"YzllYTBkNmQwOWRlZGY1YWEyYWI5.\""}}
    end

    it "with contacts" do
      elements = GContacts::List.new(parser.parse(File.read("spec/responses/contacts/all.xml")))

      expected = [
        {"id"=>"http://www.google.com/m8/feeds/contacts/john.doe%40gmail.com/full/fd8fb1a55f2916e", "atom:category"=>{"@scheme"=>"http://schemas.google.com/g/2005#kind", "@term"=>"http://schemas.google.com/g/2008#contact"}, "atom:content"=>{"@type"=>"text"}, "atom:title"=>"Steve Stephson", "gd:name"=>{"gd:fullName"=>"Steve Stephson", "gd:givenName"=>"Steve", "gd:familyName"=>"Stephson"}, "gd:email"=>[{"@rel"=>"http://schemas.google.com/g/2005#other", "@address"=>"steve.stephson@gmail.com", "@primary"=>"true"}, {"@rel"=>"http://schemas.google.com/g/2005#other", "@address"=>"steve@gmail.com"}], "gd:phoneNumber"=>["3005004000", "+130020003000"],  "gContact:groupMembershipInfo"=>{"@deleted"=>"false", "@href"=>"http://www.google.com/m8/feeds/groups/john.doe%40gmail.com/base/6"}, "@xmlns:atom"=>"http://www.w3.org/2005/Atom", "@xmlns:gd"=>"http://schemas.google.com/g/2005", "@xmlns:gContact"=>"http://schemas.google.com/contact/2008", "@gd:etag"=>"\"OWUxNWM4MTEzZjEyZTVjZTQ1Mjgy.\""},

        {"id"=>"http://www.google.com/m8/feeds/contacts/john.doe%40gmail.com/full/894bc75ebb5187d", "atom:category"=>{"@scheme"=>"http://schemas.google.com/g/2005#kind", "@term"=>"http://schemas.google.com/g/2008#contact"}, "atom:content"=>{"@type"=>"text"}, "atom:title"=>"Jill Doe", "gd:name"=>{"gd:fullName"=>"Jill Doe", "gd:givenName"=>"Jill", "gd:familyName"=>"Doe"}, "@xmlns:atom"=>"http://www.w3.org/2005/Atom", "@xmlns:gd"=>"http://schemas.google.com/g/2005", "@xmlns:gContact"=>"http://schemas.google.com/contact/2008", "@gd:etag"=>"\"ZGRhYjVhMTNkMmFhNzJjMzEyY2Ux.\""},

        {"id"=>"http://www.google.com/m8/feeds/contacts/john.doe%40gmail.com/full/cd046ed518f0fb0", "atom:category"=>{"@scheme"=>"http://schemas.google.com/g/2005#kind", "@term"=>"http://schemas.google.com/g/2008#contact"}, "atom:content"=>{"@type"=>"text"}, "atom:title"=>"Dave \"Terry\" Pratchett", "gd:name"=>{"gd:fullName"=>"Dave \"Terry\" Pratchett", "gd:givenName"=>"Dave", "gd:additionalName"=>"\"Terry\"", "gd:familyName"=>"Pratchett"}, "gd:organization"=>{"gd:orgName"=>"Foo Bar Inc", "@rel"=>"http://schemas.google.com/g/2005#work"}, "gd:email"=>{"@rel"=>"http://schemas.google.com/g/2005#home", "@address"=>"dave.pratchett@gmail.com", "@primary"=>"true"}, "gd:phoneNumber"=>"7003002000", "gContact:groupMembershipInfo"=>{"@deleted"=>"false", "@href"=>"http://www.google.com/m8/feeds/groups/john.doe%40gmail.com/base/6"}, "@xmlns:atom"=>"http://www.w3.org/2005/Atom", "@xmlns:gd"=>"http://schemas.google.com/g/2005", "@xmlns:gContact"=>"http://schemas.google.com/contact/2008", "@gd:etag"=>"\"ZWVhMDQ0MWI0MWM0YTJkM2MzY2Zh.\""},

        {"id"=>"http://www.google.com/m8/feeds/contacts/john.doe%40gmail.com/full/a1941d3d13cdc66", "atom:category"=>{"@scheme"=>"http://schemas.google.com/g/2005#kind", "@term"=>"http://schemas.google.com/g/2008#contact"}, "atom:content"=>{"@type"=>"text"}, "atom:title"=>"Jane Doe", "gd:name"=>{"gd:fullName"=>"Jane Doe", "gd:givenName"=>"Jane", "gd:familyName"=>"Doe"}, "gd:email"=>{"@rel"=>"http://schemas.google.com/g/2005#home", "@address"=>"jane.doe@gmail.com", "@primary"=>"true"}, "gd:phoneNumber"=>"16004003000", "gd:structuredPostalAddress"=>{"gd:formattedAddress"=>"5 Market St\n        San Francisco\n        CA", "gd:street"=>"5 Market St", "gd:city"=>"San Francisco", "gd:region"=>"CA", "@rel"=>"http://schemas.google.com/g/2005#home"}, "gContact:groupMembershipInfo"=>{"@deleted"=>"false", "@href"=>"http://www.google.com/m8/feeds/groups/john.doe%40gmail.com/base/6"}, "@xmlns:atom"=>"http://www.w3.org/2005/Atom", "@xmlns:gd"=>"http://schemas.google.com/g/2005", "@xmlns:gContact"=>"http://schemas.google.com/contact/2008", "@gd:etag"=>"\"Yzg3MTNiODJlMTRlZjZjN2EyOGRm.\""}
      ]

      elements.each do |element|
        element.category.should == "contact"

        # The extra tags around this are to ensure the test works in JRuby which has a stricter parser
        # and requires the presence of the xlns:#### tags to properly extract data. This isn't an issue with LibXML.

        parser.parse("<feed xmlns='http://www.w3.org/2005/Atom' xmlns:gContact='http://schemas.google.com/contact/2008' xmlns:gd='http://schemas.google.com/g/2005' xmlns:batch='http://schemas.google.com/gdata/batch'>#{element.to_xml}</feed>")["feed"]["atom:entry"].should == expected.shift
      end

      expected.should have(0).items
    end

    it "with groups" do
      elements = GContacts::List.new(parser.parse(File.read("spec/responses/groups/all.xml")))

      expected = [
          {"atom:entry"=>{"id"=>"http://www.google.com/m8/feeds/groups/john.doe%40gmail.com/full/6", "atom:category"=>{"@scheme"=>"http://schemas.google.com/g/2005#kind", "@term"=>"http://schemas.google.com/g/2008#group"}, "atom:content"=>"System Group: My Contacts", "atom:title"=>"System Group: My Contacts", "gContact:systemGroup"=>{"@id"=>"Contacts"}, "@xmlns:atom"=>"http://www.w3.org/2005/Atom", "@xmlns:gd"=>"http://schemas.google.com/g/2005", "@xmlns:gContact"=>"http://schemas.google.com/contact/2008", "@gd:etag"=>"\"YWJmYzA.\""}},

          {"atom:entry"=>{"id"=>"http://www.google.com/m8/feeds/groups/john.doe%40gmail.com/full/ada43d293fdb9b1", "atom:category"=>{"@scheme"=>"http://schemas.google.com/g/2005#kind", "@term"=>"http://schemas.google.com/g/2008#group"}, "atom:content"=>"Misc", "atom:title"=>"Misc", "@xmlns:atom"=>"http://www.w3.org/2005/Atom", "@xmlns:gd"=>"http://schemas.google.com/g/2005", "@xmlns:gContact"=>"http://schemas.google.com/contact/2008", "@gd:etag"=>"\"QXc8cDVSLyt7I2A9WxNTFUkLRQQ.\""}}
      ]

      elements.each do |element|
        element.category.should == "group"
        parser.parse(element.to_xml).should == expected.shift
      end

      expected.should have(0).items
    end
  end

  context 'Check hashed attributes' do
    let(:element) {GContacts::Element.new(parser.parse(File.read("spec/responses/contacts/get.xml"))["entry"])}

    it '#hashed_email_addresses' do
      element.hashed_email_addresses.should == {"work"=>["casey@gmail.com"], "home"=>["casey.1900@gmail.com", "casey_case@gmail.com"]}
    end

    it '#hashed_addresses' do
      element.hashed_addresses.should == {"home"=>["Xolo\n      Dome\n      Krypton"], "work"=>["Nokia Lumia 720\n      Finland\n      Earth"]}
    end

    it '#hashed_phone_numbers' do
      element.hashed_phone_numbers.should == {"mobile"=>["3005004000"], "work"=>["+130020003000"]}
    end
  end

  context 'Aggregate Contact groups' do
    let(:element) { GContacts::Element.new(parser.parse(File.read("spec/responses/contacts/multiple_group.xml"))["entry"]) }
    let(:group)   { element.groups }

    it '#groups' do
      group.count.should == 2
      group.map{ |g| g[:group_href] }.should_not be_empty
      group.map{ |g| g[:group_id] }.should_not be_empty
      group.map{ |g| g[:group_id] }.should include('6', '3d55e0800e9fe827')
    end
  end

  context '#update_groups updates Contact groups' do
    let(:element)         { GContacts::Element.new(parser.parse(File.read("spec/responses/contacts/multiple_group.xml"))["entry"]) }
    let(:new_group)       { 'http://www.google.com/m8/feeds/groups/john.doe%40gmail.com/base/12dsd121as52' }
    let(:updated_element) { parser.parse(File.read("spec/responses/contacts/update_with_group.xml"))["entry"] }

    it 'should return nil if args is empty' do
      element.update_groups().should be_nil
    end

    it 'should remove old groups from a contact' do
      element.groups.count.should == 2
      element.should_receive(:update_groups).with(new_group).once.and_return(updated_element)
      result = element.update_groups(new_group)

      result['gContact:groupMembershipInfo']['@href'].should_not match(/3d55e0800e9fe827/)
    end

    it 'should update with new groups' do
      element.should_receive(:update_groups).with(new_group).once.and_return(updated_element)
      result = element.update_groups(new_group)

      result['gContact:groupMembershipInfo'].should_not be_nil
      result['gContact:groupMembershipInfo']['@deleted'].should == 'false'
      result['gContact:groupMembershipInfo']['@href'].should match(new_group)
    end
  end

  context 'Other attributes' do
    let(:element) { GContacts::Element.new(parser.parse(File.read("spec/responses/contacts/contact_with_all_data.xml"))["entry"]) }

    context '#data should contain other attributes' do
      let!(:data) { element.data }

      it '#birthday' do
        data['gContact:birthday'].should_not be_empty
        data['gContact:birthday'][0].keys.should include("@when")
        data['gContact:birthday'].should include({"@when"=>"1989-09-10"})
      end

      it '#organisation' do
        data['gd:organization'].should_not be_empty
        data['gd:organization'][0].keys.should include('gd:orgName', 'gd:orgTitle')
      end
    end

    context '#birthday' do
      it 'GContacts::Element should have method called birthday' do
        lambda { element.birthday }.should_not raise_error
      end

      it 'should return birthday of a contact' do
        element.birthday.should_not be_nil
        element.birthday.class.should == Hash
        element.birthday.should == { date: '1989-09-10' }
      end

      it 'should return NIL if no birthday is specified' do
        element = GContacts::Element.new
        element.birthday.should be_nil
      end
    end

    context '#organization' do
      it 'GContacts::Element should have method called organization' do
        lambda { element.organization }.should_not raise_error
      end

      it 'should return organization data of a contact' do
        element.organization.should_not be_nil
        element.organization.class.should == Hash
        element.organization.keys.should include('gd:orgName', 'gd:orgTitle')
      end

      it 'should return NIL if no organization is specified' do
        element = GContacts::Element.new
        element.organization.should be_nil
      end
    end

    context '#org_name' do
      it 'GContacts::Element should have method called org_name' do
        lambda { element.org_name }.should_not raise_error
      end

      it 'should return organization data of a contact' do
        element.org_name.should_not be_nil
        element.org_name.should =~ /Organisation/
      end

      it 'should return NIL if no organization is specified' do
        element = GContacts::Element.new
        element.org_name.should be_nil
      end
    end

    context '#org_title' do
      it 'GContacts::Element should have method called org_title' do
        lambda { element.org_title }.should_not raise_error
      end

      it 'should return organization title of a contact' do
        element.org_title.should_not be_nil
        element.org_title.should =~ /Developer/
      end

      it 'should return NIL if no orgTitle is specified' do
        element = GContacts::Element.new
        element.org_title.should be_nil
      end
    end
  end
end
