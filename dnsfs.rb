
require 'optparse'
require 'base64'
require 'resolv'

$options = {}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: --generate <folder>\n" + 
                "       --download <domain>\n\n"

  $options[:mode] = nil

  opts.on('-g', '--generate', 'Generate DNS entries') do 
    if $options[:mode]
      STDERR.puts "Choose either --generate OR --download."
      STDERR.puts opts
      exit
    else 
      $options[:mode] = :generate
    end
  end

  opts.on('-d', '--download', 'List files and download') do 
    if $options[:mode]
      STDERR.puts "Choose either --generate OR --download."
      STDERR.puts opts
      exit
    else 
      $options[:mode] = :download
    end
  end

  $options[:nameserver] = nil
  opts.on('-n', '--nameserver NS', 'Nameserver to use for downloading') do |ns|
    $options[:nameserver] = ns
  end

end

begin
  optparse.parse!
rescue OptionParser::InvalidOption
  STDERR.puts "Invalid option"
  STDERR.puts optparse
  exit
end

if $options[:mode].nil?
  STDERR.puts "Choose either --generate OR --download."
  STDERR.puts optparse
  exit
end

if ARGV.length != 1
  if $options[:mode] == :generate
    STDERR.puts "Please specify a source folder."
  else
    STDERR.puts "Please specify a domain name."
  end
  STDERR.puts optparse
  exit
end

def generateEntries(source_dir)
  file_number = 1
  Dir.foreach(source_dir) do |item|
    next if item == '.' or item == '..'
    path = File.join(source_dir, item)
    if generateEntriesForFile(file_number, path)
      file_number += 1
    end
  end
  # FIXME: parameterize the 'dnsfs'
  puts "f#{file_number}info.dnsfs IN TXT \"~EOL~\""
end

def generateEntriesForFile(n, path)
  size = File.size(path)
  if size > 10 * 1024 * 1024
    STDERR.puts "Skipping #{path}, it's too big."
    return false;
  end

  name = File.basename(path)

  # Directory entry
  puts "f#{n}info.dnsfs IN TXT \"Name: #{name} / Size: #{size}\""

  part = 1
  part_size = 189
  File.open(path, 'r') do |f|
    while part_contents = f.read(part_size)
      # We use encode64 instead of strict_encode64 for backwards compatibility.
      part_base64 = Base64.encode64(part_contents).gsub("\n",'')
      puts "f#{n}p#{part}.dnsfs IN TXT \"#{part_base64}\""
      part += 1
    end
  end

  puts "f#{n}p#{part}.dnsfs IN TXT \"~EOF~\""

  return true;
end

def interactiveDownload(domain)
  file_info = interactiveSelectFile(domain)
  return if file_info.nil?
  dest_path = File.join("/tmp/", file_info[:name])

  if File.exist?(dest_path)
    puts "ERROR: File already exists in #{dest_path}.\n"
    return
  end

  File.open(dest_path, 'w') do |f|
    part = 1
    while part_data = getFilePart(domain, file_info[:number], part)
      print "."
      STDOUT.flush
      f.write(part_data)
      part += 1
    end
    puts ""
  end

  puts "File written to #{dest_path}."
end

def interactiveSelectFile(domain)
  files = []
  file_number = 1
  while file_info = getFileInfo(domain, file_number)
    files << file_info
    file_number += 1
  end

  if files.empty?
    puts "No files there."
    return nil
  else
    files.each_with_index do |file, index|
      puts "#{index+1}. #{file[:name]} (size: #{file[:size]} bytes)"
    end

    puts "Which one?"
    index = STDIN.gets.strip.to_i
    if index < 1 || index > files.count
      puts "Bad selection."
      return nil
    end
    return files[index-1]
  end
end

def getFileInfo(domain, file_number)
  dns = getResolver()
  info = dns.getresource("f#{file_number}info." + domain, Resolv::DNS::Resource::IN::TXT)
  info = info.data()
  file = {}
  file[:number] = file_number
  if info == "~EOL~"
    return nil
  end
  if /Name: (.+) \/ Size: (\d+)/.match(info)
    file[:name] = $1
    file[:size] = $2.to_i
  else
    return nil
  end
  return file
rescue Resolv::ResolvError
  return nil
end

def getFilePart(domain, file_number, part_number)
  dns = getResolver()
  info = dns.getresource("f#{file_number}p#{part_number}." + domain, Resolv::DNS::Resource::IN::TXT)
  info = info.data()
  if info == "~EOF~"
    return nil
  else
    return Base64.decode64(info)
  end
rescue Resolv::ResolvError
  # FIXME: should expect a random error once in a while... maybe retry?
  return nil
end

def getResolver
  if $options[:nameserver]
    return Resolv::DNS.new(:nameserver => $options[:nameserver])
  else
    return Resolv::DNS.new()
  end
end

if $options[:mode] == :generate
  generateEntries(ARGV[0])
elsif $options[:mode] == :download
  interactiveDownload(ARGV[0])
end
