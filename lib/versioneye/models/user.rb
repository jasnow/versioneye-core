class User < Versioneye::Model

  A_EMAIL_REGEX = /[\S]+\@[\S]+\.[\S]+\z/i

  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::MultiParameterAttributes

  field :username          , type: String
  field :fullname          , type: String
  field :prev_fullname     , type: String
  field :email             , type: String
  field :email_inactive    , type: Boolean, default: false # Inactive recipients are ones that have generated a hard bounce or a spam complaint
  field :encrypted_password, type: String
  field :salt              , type: String
  field :admin             , type: Boolean, default: false
  field :deleted           , type: Boolean, default: false
  field :verification      , type: String
  field :terms             , type: Boolean
  field :datenerhebung     , type: Boolean
  field :privacy_products  , type: String, default: 'everybody'
  field :privacy_comments  , type: String, default: 'everybody'

  field :description, type: String
  field :location   , type: String
  field :time_zone  , type: String
  field :blog       , type: String

  field :promo_code, type: String
  field :refer_name, type: String
  field :free_private_projects, type: Integer, default: 0

  # TODO refactor this in github_account, bitbucket_account
  # create own models for that und connect them to user

  field :github_id   , type: String
  field :github_login, type: String #username on github
  field :github_token, type: String
  field :github_scope, type: String

  field :bitbucket_id,     type: String
  field :bitbucket_login,  type: String #username on bitbucket
  field :bitbucket_token,  type: String
  field :bitbucket_secret, type: String
  field :bitbucket_scope,  type: String

  field :stripe_token      , type: String
  field :stripe_customer_id, type: String

  field :email_send_error, type: String

  # *** RELATIONS START ***
  belongs_to :plan
  has_one    :billing_address
  has_one    :user_notification_setting
  has_one    :testimonial
  has_many   :projects
  has_many   :github_repos
  has_many   :bitbucket_repos

  has_and_belongs_to_many :products
  # *** RELATIONS END ***

  validates_presence_of :username          , :message => 'is mandatory!'
  validates_presence_of :fullname          , :message => 'is mandatory!'
  validates_presence_of :email             , :message => 'is mandatory!'
  validates_presence_of :encrypted_password, :message => 'is mandatory!'
  validates_presence_of :salt              , :message => 'is mandatory!'
  validates_presence_of :terms             , :message => 'is mandatory!'

  validates_uniqueness_of :username          , :message => 'exist already.'
  validates_uniqueness_of :email             , :message => 'exist already.'

  validates_length_of :username, minimum: 2, maximum: 50, :message => 'length is not ok'
  validates_length_of :fullname, minimum: 2, maximum: 50, :message => 'length is not ok'

  validates_format_of :username, with: /\A[a-zA-Z0-9_]+\z/
  validates_format_of :email   , :with => A_EMAIL_REGEX, :message => 'is not valid.'

  before_validation :downcase_email

  scope :by_verification, ->(code){where(verification: code)}
  scope :live_users     , where(verification: nil, deleted: false)
  scope :follows_equal  , ->(n){where(:product_ids.count.eq(n))}
  scope :follows_least  , ->(n){where(:product_ids.count >= n)}
  scope :follows_max    , ->(n){where(:product_ids.count <= n)}

  attr_accessor :password, :new_username
  attr_accessible :fullname, :username, :email, :password, :new_username, :terms, :datenerhebung, :verification, :terms, :datenerhebung


  def save(*arg)
    encrypt_password if new_record?
    return false if self.terms == false || self.terms == nil
    return false if self.datenerhebung == false || self.datenerhebung == nil
    super
  end

  def to_param
    username
  end

  def to_s
    result = "#{username} / #{fullname} / #{email}"
    result += " - verification: #{verification}" if verification
    result += " - verified account " if verification.nil?
    result += " - deleted " if deleted
    result
  end

  def create_verification
    random = create_random_value
    self.verification = secure_hash("#{random}--#{username}")
  end

  def send_verification_email
    UserMailer.verification_email(self, self.verification, self.email).deliver
  rescue => e
    User.log.error e.message
    User.log.error e.backtrace.join('\n')
  end

  def self.send_verification_reminders
    users = User.where( :verification.ne => nil )
    users.each do |user|
      next if user.email_inactive
      user.send_verification_reminder
    end
  end

  def send_verification_reminder
    if !self.verification.nil? && self.deleted != true
      UserMailer.verification_email_reminder(self, self.verification, self.email).deliver
    end
  rescue => e
    User.log.error e.message
    User.log.error e.backtrace.join('\n')
  end

  def send_suggestions
    return nil if deleted || email_inactive
    UserMailer.suggest_packages_email(self).deliver
  rescue => e
    User.log.error e.message
    User.log.error e.backtrace.join('\n')
    nil
  end

  def create_username
    name = fullname.strip
    if name.include?(" ")
      name = name.gsub!(" ", "")
    end
    if name.include?("-")
      name = name.gsub!("-", "")
    end
    user = User.find_by_username(name)
    if user
      name = name + create_random_value
    end
    self.username = name
  end

  def self.activate!(verification)
    return false if verification.nil? || verification.strip.empty?
    user = User.where(verification: verification).shift
    if user
      user.verification = nil
      user.save
      return true
    end
    return false
  end

  def activated?
    verification.nil?
  end

  def self.find_by_username( username )
    return nil if username.nil? || username.strip.empty?
    User.where( username: /\A#{username}\z/i ).shift
  end

  def self.find_by_email(email)
    return nil if email.nil? || email.strip.empty?
    user = User.where(email: email).shift
    if user.nil?
      user = User.where(email: /\A#{email}\z/i).shift
    end
    user
  end

  def self.find_by_id( id )
    return nil if id.nil?
    return User.find(id.to_s)
  rescue => e
    log.error e.message
    log.error e.backtrace.join("\n")
    nil
  end

  def self.find_by_ids( ids )
    User.where(:id.in => ids)
  rescue => e
    log.error e.message
    log.error e.backtrace.join("\n")
    nil
  end

  def self.find_all( page_count )
    User.all().desc(:created_at).paginate(page: page_count, per_page: 30)
  end

  def emails
    UserEmail.where(user_id: self._id.to_s)
  end

  def emails_verified
    UserEmail.where(user_id: self._id.to_s, verification: nil)
  end

  def get_email email
    UserEmail.where( user_id: self._id.to_s, email: email ).shift
  end

  def has_password? submitted_password
    self.encrypted_password == encrypt(submitted_password)
  end

  def self.find_by_github_id github_id
    return nil if github_id.nil? || github_id.strip.empty?
    User.where(github_id: github_id).shift
  end

  def self.find_by_bitbucket_id(bitbucket_id)
    return nil if bitbucket_id.to_s.strip.empty?
    User.where(bitbucket_id: bitbucket_id).shift
  end

  def github_account_connected?
    !self.github_id.to_s.empty? && !self.github_token.to_s.empty?
  end

  def bitbucket_account_connected?
    !self.bitbucket_id.to_s.empty? && !self.bitbucket_token.to_s.empty?
  end


  def self.follows_max(n)
    User.all.select {|user| user['product_ids'].nil? or user['product_ids'].count < n}
  end

  def self.follows_least(n)
    User.all.select {|user| !user['product_ids'].nil? and user['product_ids'].count >= n}
  end

  def self.non_followers
    User.collection.find({'product_ids.0' => {'$exists' => false}})
  end

  def self.authenticate(email, submitted_password)
    user = User.where( email: email.downcase ).shift
    return nil  if user.nil? || user.deleted
    return user if user.has_password?(submitted_password)
    return nil
  end

  def self.authenticate_with_salt(id, coockie_salt)
    return nil if !id || !coockie_salt
    user = User.find( id )
    ( user && user.salt == coockie_salt ) ? user : nil
  rescue => e
    log.error e.message
    log.error e.backtrace.join("\n")
    nil
  end

  def self.authenticate_with_apikey(token)
    user_api = Api.where(api_key: token).shift
    return nil if user_api.nil?

    user = User.find_by_id(user_api.user_id)
    return nil if user.nil?

    user
  end

  def self.username_valid?(username)
    user = User.find_by_username(username)
    return user.nil?
  end

  def self.email_valid?(email)
    user = find_by_email(email)
    user_email = UserEmail.find_by_email(email)
    return user.nil? && user_email.nil?
  end

  def password_valid?(password)
    enc_password = encrypt(password)
    enc_password.eql?(encrypted_password)
  end

  def update_password(verification_code, password)
    user = User.by_verification(verification_code).first
    return false if user.nil?
    self.password = password
    encrypt_password
    save
  end

  def update_from_github_json(json_user, token)
    self.fullname     = json_user['name']
    self.username     = json_user['login']
    self.github_id    = json_user['id']
    self.github_login = json_user['login']
    self.github_token = token
    self.password     = create_random_value
    if self.username.nil? || self.username.empty?
      self.username = create_random_value
    end
    user = User.find_by_username(self.username)
    unless user.nil?
      random_value = create_random_value
      self.username = "#{self.username}_#{random_value}"
    end
    self.username = replacements_for_username( self.username )
    if self.fullname.nil? || self.fullname.empty?
      self.fullname = self.username
    end
  end

  def update_from_bitbucket_json(user_info, token, secret, scopes = "read_write")
    self[:username] = user_info[:username]

    if self[:username].to_s.empty?
      self.username = "unknown_#{SecureRandom.hex(8)}"
    end

    user = User.find_by_username(self[:username])
    unless user.nil?
      random_value = SecureRandom.hex(8)
      self.username = "#{self[:username]}_#{random_value}"
    end

    self[:fullname]         = user_info[:display_name]
    self[:bitbucket_id]     = user_info[:username]
    self[:bitbucket_login]  = user_info[:username]
    self[:bitbucket_token]  = token
    self[:bitbucket_secret] = secret
    self[:bitbucket_scope]  = scopes
  end

  def replacements_for_username( username )
    username = username.gsub(".", "")
    username = username.gsub("-", "")
    username.gsub("_", "")
  end

  def fetch_or_create_billing_address
    if self.billing_address.nil?
      self.billing_address = BillingAddress.new
      self.billing_address.name = self.fullname
      self.billing_address.save
    end
    self.billing_address
  end

  #-- ElasticSearch mapping ------------------
  def to_indexed_json
    {
      :_id => self.id.to_s,
      :_type => "user",
      :fullname => self[:fullname],
      :username => self[:username],
      :email => self[:email]
    }
  end

  def encrypt_password
    self.salt = make_salt if new_record?
    self.encrypted_password = encrypt(password)
  end

  private

    def create_random_token(length = 25)
      SecureRandom.urlsafe_base64(length)
    end

    def create_random_value
      chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
      value = ""
      10.times { value << chars[rand(chars.size)] }
      value
    end

    def downcase_email
      self.email = self.email.downcase if self.email.present?
    end

    def make_salt
      secure_hash("#{Time.now.utc}--#{password}")
    end

    def encrypt(string)
      secure_hash("#{salt}--#{string}")
    end

    def secure_hash(string)
      Digest::SHA2.hexdigest(string)
    end

end
