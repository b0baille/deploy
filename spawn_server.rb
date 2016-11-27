require "aws-sdk"
require "base64"

# config
REGION = ENV["REGION"] || "eu-west-1"
ACCESS_KEY = ENV["ACCESS_KEY"]
SECRET_ACCESS_KEY = ENV["SECRET_ACCESS_KEY"]
KEY_NAME = ENV["KEY_NAME"]
SECURITY_GROUP = ENV["SECURITY_GROUP"]

NUMBER_OF_INSTANCES = 1
AMI_ID = "ami-b7db91c4"
INSTANCE_TYPE = ENV["INSTANCE_TYPE"] || "t1.micro"
INSTANCE_NAME = ENV["INSTANCE_NAME"] || "test-robin"

MYSQL_PASSWORD = ENV["MYSQL_PASSWORD"]

%w(MYSQL_PASSWORD SECURITY_GROUP KEY_NAME SECRET_ACCESS_KEY ACCESS_KEY).each do |var|
  if ENV[var] == nil || ENV[var] == 0
    puts "plase set the #{var} environment variable"
    exit 1
  end
end

client = Aws::EC2::Client.new(
  region: REGION,
  access_key_id: ACCESS_KEY,
  secret_access_key: SECRET_ACCESS_KEY
)

puts "Creating instance"

# start a new instance
# doc: http://docs.aws.amazon.com/sdkforruby/api/Aws/EC2/Client.html#run_instances-instance_method
resp = client.run_instances({
  min_count: NUMBER_OF_INSTANCES,
  max_count: NUMBER_OF_INSTANCES,
  image_id: AMI_ID,
  instance_type: INSTANCE_TYPE,
  key_name: KEY_NAME,
  security_group_ids: [SECURITY_GROUP],
  user_data: Base64.encode64(File.read("cloud_config.yaml").sub("$MYSQL_PASSWORD", MYSQL_PASSWORD))
});

instance_id = resp.instances[0].instance_id

client.create_tags({
  resources: [
    instance_id
  ],
  tags: [
    key: "Name",
    value: INSTANCE_NAME,
  ]
})

puts "Waiting for instance to boot ..."

instance_info = nil

while true do
  sleep(5)
  describe_resp = client.describe_instances({instance_ids: [instance_id]})
  instance_info = describe_resp.reservations[0].instances[0]
  break if instance_info.state.name == "running" && instance_info.public_dns_name != ""
  puts "..."
end

puts "Instance #{INSTANCE_NAME} (#{instance_info.instance_type}) deployed:"
puts "Public dns: #{instance_info.public_dns_name}"
puts "ssh core@#{instance_info.public_dns_name} using key #{instance_info.key_name}"
puts "mysql is running on port 3306. User: root password: #{MYSQL_PASSWORD}"
