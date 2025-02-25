class GeneralInfo < ApplicationRecord
  has_many :gallery, dependent: :destroy, foreign_key: 'GeneralInfo_id' 
  has_many :messages, dependent: :destroy
  has_many :reviews, dependent: :destroy
  has_one :login_info

  # For follow feature
  has_many(:follows, :foreign_key => :followee, :dependent => :destroy)
  has_many(:follows_from, :class_name => :Follow,
      :foreign_key => :follower, :dependent => :destroy)
  has_many :followers, :through => :follows, :source => :follower
  has_many :follows_others, :through => :follows_from, :source => :followee

  # NXTFolio : Added in Spring 2023 for tagging feature
  has_many :gallery_taggings
  has_many :tagged_gallery, through: :gallery_taggings, source: :gallery

  validates_presence_of :first_name
  validates_presence_of :last_name
  validates_presence_of :company
  validates_presence_of :industry
  validates_presence_of :highlights
  validates_presence_of :country
  validates_presence_of :state
  validates_presence_of :city
  validates_presence_of :emailaddr
  # validates_presence_of :job_name
  serialize :job_attr, Hash


  # validates :phone, numericality: true

  mount_uploader :profile_picture, AvatarUploader
  mount_uploader :cover_picture, CoverUploader
  mount_uploaders :gallery_pictures, GalleryUploader

  geocoded_by :address
  after_validation :geocode

  def address
    [city, state, country].compact.join(", ")
  end

  # def name
  #   self[:name]
  # end

  def self.search searchArg
    location = nil
    if searchArg[:location].present? and searchArg[:location] != ''
      location = searchArg[:location]
    end

    distance = 20
    if searchArg[:distance].present? and searchArg[:distance] != ''
      distance = Integer(searchArg[:distance])
    end

    if location != nil
      query = GeneralInfo.near(location, distance)
    else
      query = GeneralInfo.all
    end

    if searchArg[:first_name].present?
      if searchArg[:first_name_regex] == 'Contains'
        searchArg[:first_name] = "%" + searchArg[:first_name] + "%"
      elsif searchArg[:first_name_regex] == 'Starts With'
        searchArg[:first_name] = searchArg[:first_name] + "%"
      elsif searchArg[:first_name_regex] == 'Ends With'
        searchArg[:first_name] = "%" + searchArg[:first_name]
      elsif searchArg[:first_name_regex] == 'Exactly Matches'
        searchArg[:first_name] = searchArg[:first_name]
      end
      query = query.where("first_name ILIKE ?", searchArg[:first_name])
    end

    if searchArg[:last_name].present?
      if searchArg[:last_name_regex]=='Contains'
        searchArg[:last_name]="%"+searchArg[:last_name]+"%"
      elsif searchArg[:last_name_regex]=='Starts With'
        searchArg[:last_name]=searchArg[:last_name]+"%"
      elsif searchArg[:last_name_regex]=='Ends With'
        searchArg[:last_name]="%"+searchArg[:last_name]
      elsif searchArg[:last_name_regex]=='Exactly Matches'
        searchArg[:last_name]=searchArg[:last_name]
      end
      query = query.where("last_name ILIKE ?", searchArg[:last_name])
    end

    if searchArg[:gender].present? and searchArg[:gender] != 'Any'
      query = query.where("gender ILIKE ?", searchArg[:gender])
    end


    if searchArg[:compensation].present? and searchArg[:compensation] != 'Any'
      searchArg[:compensation]="%"+searchArg[:compensation]+"%"
      query = query.where("compensation ILIKE ?", searchArg[:compensation])
    end

    if searchArg[:job_type].present? and searchArg[:job_type] != 'Any'
      query = query.where("job_name ILIKE ?", searchArg[:job_type])
    end

    return query
  end

  # Sets appearance of profile view attributes
  def attribute_values
    @attribute_values = Hash.new
    @attribute_values[:name] = "Name: " + self.first_name.to_s + " " + self.last_name.to_s
    @attribute_values[:phone]= "Phone: "+self.phone.to_s
    @attribute_values[:birthday] = "Birthday: " + self.month_ofbirth.to_s + " / " + self.day_ofbirth.to_s + " / " + self.year_ofbirth.to_s
    @attribute_values[:gender] = "Gender: " + self.gender.to_s
    @attribute_values[:location] = "Location: " + self.city.to_s + ", " + self.state.to_s + ", " + self.country.to_s
    @attribute_values[:compensation] = "Compensation: " + self.compensation.to_s
    @attribute_values[:facebook_link] = "Facebook: " + self.facebook_link.to_s
    @attribute_values[:linkedIn_link] = "LinkedIn: " + self.linkedIn_link.to_s
    @attribute_values[:instagram_link] = "Instagram: " + self.instagram_link.to_s
    @attribute_values[:personalWebsite_link] = "Personal website: " + self.personalWebsite_link.to_s
    @attribute_values[:bio] = "Biography: " + self.bio.to_s
    @attribute_values[:job_name] = self.job_name.to_s
    @attribute_values[:job_attr] = self.job_attr
    @attribute_values
  end

  # Create/Define Jobs by dynamically creating classes

  @@AcceptableAttrTypes = ["Integer", "Float", "String"]

  @@Job_List = Array.new
  @@Job_Attr = Hash.new
  @@Attr_Type = Hash.new
  # Need code to populate job based off of existing database (For server reboots)

  def self.see_Jobs
    jobList = @@Job_List
    jobList.delete('Admin')
    jobList
  end

  def self.see_Types
    @@AcceptableAttrTypes
  end

  def self.check_Job?(jobName)
    if(jobName == 'Admin')
      false
    else
      @@Job_List.include?(jobName)
    end
  end

  def self.delete_Job(jobName)
    if (self.check_Job?(jobName))
      @@Job_List.delete(jobName)
      jobString = '\''
      @@Job_List.each do |job|
        jobString = jobString + job + '\''
      end
      $redis.set('jobList', jobString)
      $redis.del(jobName)

      # Code here to edit the database entries
    end
  end


  def self.load_Job_File()
    jobString = $redis.get('jobList')
    jobArray = Array.new
    if(jobString != nil && jobString != "")
      jobArray = jobString.scan(/\w+/)
      jobArray.each do |job|
        attrString = $redis.get(job)
        if(attrString != nil) # If there's a redis for this job  
          eachAttrMatch = attrString.to_enum(:scan, /\w+(\s\w+)*(%)/).map {Regexp.last_match}
          eachTypeMatch = attrString.to_enum(:scan, /\w+(\s\w+)*(,|')/).map {Regexp.last_match} # Not really implemented yet, just a copy of the attribute name
          eachAttrMatch = eachAttrMatch.flatten
          eachTypeMatch = eachTypeMatch.flatten

          self.create_Job(job, false)
          if(eachAttrMatch != nil && eachAttrMatch.size > 0)
            eachAttrMatch.each do |attr|
              job.constantize.add_Attr(attr.to_s.chop, "String", false) # Add the types you get from TypeMatch to further specialize this
            end
            job.constantize.update_File()
          end
        end
      end
    else # Job Redis is empty/ never been used. Initialize Admin role
      $redis.set('jobList', '\'Admin\'')
      $redis.set('Admin', '')
      self.create_Job('Admin', false)
    end

    #@@Job_List = jobArray  

  end

  def self.create_Job (className, writeToFile = true)

    # Code to validate the job name has chars only will go here

    if(self.check_Job?(className.upcase_first) == false && className != 'Admin' && className != 'admin')
      @@Job_List.push(className.upcase_first)
      @@Job_Attr[className.upcase_first] = Array.new
      @@Attr_Type[className.upcase_first] = Array.new


      # Create entry in Job File List

      creator = Object.const_set(className.upcase_first, Class.new {



        def self.display_Name()
          self.name
        end

        def display_Name()
          self.display_Name()
        end

        # def initialize()

        # end

        def self.add_Attr(attr_Name, attr_Type = "String", writeToRedis = true)
          # If Name not in hash already
          if(@@Job_Attr[self.name].include?(attr_Name) == false)
            @@Job_Attr[self.name].push(attr_Name)
            @@Attr_Type[self.name].push(attr_Type)
            if(writeToRedis)
              self.update_File
            end
          end

          # Else Error, name already exists
        end

        def add_Attr(attr_Name, attr_Type = "String", writeToRedis = true)
          self.add_Attr(attr_Name, attr_Type, writeToRedis)
        end

        def self.edit_Attr(attr_Name, new_Name, new_Type = nil)
          indexLoc = @@Job_Attr[self.name].find_index(attr_Name)

          if(indexLoc)
            @@Job_Attr[self.name][indexLoc] = new_Name
            if(new_type != nil)
              @@Attr_Type[self.name] = new_Type
            end
            self.update_File
            # Code to run through database and edit all existing entries 
          end
        end

        def edit_Attr(attr_Name, new_Name, new_Type = nil)
          self.edit_Attr(attr_Name, new_Name, new_Type)
        end

        def self.delete_Attr(attr_Name)
          indexLoc = @@Job_Attr[self.name].find_index(attr_Name)

          if(indexLoc)
            @@Job_Attr[self.name].delete_at(indexLoc)
            @@Attr_Type[self.name].delete_at(indexLoc)
            self.update_File
            # Code to shift all attributes into place in database is in Admin controller
          end
        end

        def delete_Attr(attr_Name)
          self.delete_Attr(attr_Name)
        end

        def self.view_Attr()
          @@Job_Attr[self.name]
        end

        def view_Attr()
          self.view_Attr()
        end

        def self.view_Attr_Type(attr_Name = nil)
          if (attr_Name == nil)
            @@Attr_Type[self.name]
          else
            indexLoc = @@Attr_Type[self.name].find_index(attr_Name)

            if(indexLoc)
              @@Attr_Type[self.name][indexLoc]
            else
              nil
            end
          end
        end

        def view_Attr_Type(attr_Name)
          self.view_Attr_Type(attr_Name)
        end

        def self.update_File()
          self_Name = self.name
          attr_Body = '\''
          x = 0
          while(x < @@Job_Attr[self.name].size)
            attr_Body = attr_Body + @@Job_Attr[self.name][x] + '%' + @@Attr_Type[self.name][x] + '\''
            x = x + 1
          end
          if(attr_Body == '\'')
            attr_Body = '\'\''
          end
          #      new_line = self.display_Name + " " + attr_Body
          #      file_cont = File.read ("jobList.dat")
          #      new_cont = file_cont.gsub(/^(#{Regexp.escape(self_Name)}).*/, new_line)
          #      File.open("jobList.dat", "w") {|file| file.puts new_cont}
          $redis.set(self.name, attr_Body)
        end

        def update_File()
          self.update_File()
        end

      })

      if(writeToFile)
        jobString = '\''
        @@Job_List.each do |job|
          jobString = jobString + job + '\''
        end
        jobString = jobString + className.upcase_first + '\''
        $redis.set('jobList', jobString)
        $redis.set(className.upcase_first, '')
      end
    end
  end


  def follow(id)
    followee = GeneralInfo.find(id)
    Follow.create!(:follower => self, :followee => followee)
  end

  def unfollow(id)
    followee = GeneralInfo.find(id)
    self.follows_others.delete(followee)
  end

  def get_followers 
     self.followers
  end

  def get_users_they_follow
     self.follows_others
  end

  def self.filterBy country, state, profession, city
    #filter by profession, country, state
    @filteredUsers = profession.present? ? GeneralInfo.where(job_name: profession) : GeneralInfo.all
    # @filteredUsers = @filteredUsers.where(country: country) #United States

    #@filteredUsers = country.present? ? GeneralInfo.where(country: country) : @filteredUsers
    @filteredUsers = country.present? ? @filteredUsers.where(country: country) : @filteredUsers

    @filteredUsers = state.present? ? @filteredUsers.where(state: state) : @filteredUsers
    #adding city on filter list
    #@filteredUsers = city.present? ? @filteredUsers.where(city: city) : @filteredUsers
    @filteredUsers = city.present? ? @filteredUsers.where("LOWER(city) = ?", city.downcase) : @filteredUsers

    
    #@filteredUsers.each do |room|
    #  puts "users are: #{room[:first_name]}"
    #end


    # add travel feature
    # if the profession travels to the city within 30 days,
    # he should show up in the search results
    @filteredUsers1 = profession.present? ? GeneralInfo.where(job_name: profession) : GeneralInfo.all
    @filteredUsers1 = country.present? ? @filteredUsers1.where(travel_country: country) : @filteredUsers1
    @filteredUsers1 = state.present? ? @filteredUsers1.where(travel_state: state) : @filteredUsers1
    @filteredUsers1 = city.present? ? @filteredUsers1.where(travel_city: city) : @filteredUsers1
    # @filteredUsers1 = @filteredUsers1.where(travel_start: Date.today..30.days.from_now.to_date) + \
    #                   @filteredUsers1.where.not(travel_start: Date.today..30.days.from_now.to_date).
    @filteredUsers1 = @filteredUsers1.where(travel_start: Date.today..30.days.from_now.to_date)\
                    .or(@filteredUsers1.where(travel_end: Date.today..30.days.from_now.to_date)\
                    .or(@filteredUsers1.where('travel_start < ?', Date.today).where('travel_end > ?', Date.today) ) )
          
    return @filteredUsers.or(@filteredUsers1)
  end
end

