# Sun packaging.

require 'puppet/provider/package'

Puppet::Type.type(:package).provide :sun, :parent => Puppet::Provider::Package do
  desc "Sun's packaging system.  Requires that you specify the source for
    the packages you're managing."

  commands :pkginfo => "/usr/bin/pkginfo",
    :pkgadd => "/usr/sbin/pkgadd",
    :pkgrm => "/usr/sbin/pkgrm"

  confine :osfamily => :solaris
  defaultfor :osfamily => :solaris

  has_feature :install_options

  Namemap = {
    "PKGINST"  => :name,
    "CATEGORY" => :category,
    "ARCH"     => :platform,
    "VERSION"  => :ensure,
    "BASEDIR"  => :root,
    "VENDOR"   => :vendor,
    "DESC"     => :description,
  }

  def self.namemap(hash)
    Namemap.keys.inject({}) do |hsh,k|
      hsh.merge(Namemap[k] => hash[k])
    end
  end

  def self.parse_pkginfo(out)
    # collect all the lines with : in them, and separate them out by ^$
    pkgs = []
    pkg = {}
    out.each_line do |line|
      case line.chomp
      when /^\s*$/
        pkgs << pkg unless pkg.empty?
        pkg = {}
      when /^\s*([^:]+):\s+(.+)$/
        pkg[$1] = $2
      end
    end
    pkgs << pkg unless pkg.empty?
    pkgs
  end

  def self.instances
    parse_pkginfo(execute([command(:pkginfo), '-l'])).collect do |p|
      hash = namemap(p)
      hash[:provider] = :sun
      new(hash)
    end
  end

  # Get info on a package, optionally specifying a device.
  def info2hash(device = nil)
    cmd = [command(:pkginfo), '-l']
    cmd << '-d' << device if device
    cmd << @resource[:name]
    pkgs = self.class.parse_pkginfo(execute(cmd, :failonfail => false))
    errmsg = case pkgs.size
             when 0; 'No message'
             when 1; pkgs[0]['ERROR']
             end
    return self.class.namemap(pkgs[0]) if errmsg.nil?
    return {:ensure => :absent} if errmsg =~ /information for "#{Regexp.escape(@resource[:name])}"/
    raise Puppet::Error, "Unable to get information about package #{@resource[:name]} because of: #{errmsg}"
  end

  # Retrieve the version from the current package file.
  def latest
    info2hash(@resource[:source])[:ensure]
  end

  def query
    info2hash
  end

  def prepare_cmd(opt)
    cmd = []
    cmd << '-a' << @resource[:adminfile] if @resource[:adminfile] && opt[:adminfile]
    cmd << '-r' << @resource[:responsefile] if @resource[:responsefile] && opt[:responsefile]
    cmd << '-d' << @resource[:source] if opt[:source]
    cmd << opt[:cmd_options] if opt[:cmd_options]
    cmd << '-n' << @resource[:name]
  end

  # only looking for -G now
  def install
    raise Puppet::Error, "Sun packages must specify a package source" unless @resource[:source]
    options = {
      :adminfile    => true,
      :responsefile => true,
      :source       => true,
      :cmd_options  => @resource[:install_options]
    }
    pkgadd prepare_cmd(options)
  end

  def uninstall
    pkgrm prepare_cmd(:adminfile => true)
  end

  # Remove the old package, and install the new one.  This will probably
  # often fail.
  def update
    self.uninstall if (@property_hash[:ensure] || info2hash[:ensure]) != :absent
    self.install
  end
end
