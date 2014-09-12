# encoding: UTF-8

actions :create

attribute :domain, kind_of: String, name_attribute: true
attribute :description, kind_of: String, default: ''
attribute :aliases, kind_of: Integer, default: 10
attribute :mailboxes, kind_of: Integer, default: 10
attribute :login_username, kind_of: String, required: true
attribute :login_password, kind_of: String, required: true
attribute :db_type, equal_to: %w(mysql postgresql)
attribute :db_user, kind_of: String
attribute :db_password, kind_of: String
attribute :db_name, kind_of: String
attribute :db_host, kind_of: String
attribute :db_port, kind_of: [Fixnum, String]
attribute :ssl, kind_of: [TrueClass, FalseClass]
attribute :port, kind_of: [Fixnum, String]

def initialize(*args)
  super
  @action = :create
end
