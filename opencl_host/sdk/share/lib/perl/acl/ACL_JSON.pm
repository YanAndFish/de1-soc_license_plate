
=pod

=head1 COPYRIGHT

# (C) 1992-2018 Intel Corporation.                            
# Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack words    
# and logos are trademarks of Intel Corporation or its subsidiaries in the U.S.  
# and/or other countries. Other marks and brands may be claimed as the property  
# of others. See Trademarks on intel.com for full list of Intel trademarks or    
# the Trademarks & Brands Names Database (if Intel) or See www.Intel.com/legal (if Altera) 
# Your use of Intel Corporation's design tools, logic functions and other        
# software and tools, and its AMPP partner logic functions, and any output       
# files any of the foregoing (including device programming or simulation         
# files), and any associated documentation or information are expressly subject  
# to the terms and conditions of the Altera Program License Subscription         
# Agreement, Intel MegaCore Function License Agreement, or other applicable      
# license agreement, including, without limitation, that your use is for the     
# sole purpose of programming logic devices manufactured by Intel and sold by    
# Intel or its authorized distributors.  Please refer to the applicable          
# agreement for further details.                                                 


=head1 NAME

acl::ACL_JSON - an ascii-only JSON module, modified from the Standard Version of
JSON::PP.

=head1 DESCRIPTION

acl::ACL_JSON is a pure-Perl module that only handles ascii-encoded strings.

This module is essentially a cut-down version of the Standard Version of
JSON::PP.  It provides functionality for converting ascii JSON strings to Perl,
and Perl to ascii JSON strings.  Several of the features of the original package
have been removed.


Modification date: March 2, 2017.

=cut

package acl::ACL_JSON;

# JSON-2.0

use strict;
require Exporter;
@acl::ACL_JSON::ISA     = qw(Exporter);
$acl::ACL_JSON::VERSION = '1';
@acl::ACL_JSON::EXPORT  = qw(acl_encode_json acl_decode_json);

BEGIN {
    my @xs_compati_bit_properties = qw(ascii relaxed allow_unknown);
    my @pp_bit_properties = qw(allow_singlequote escape_slash as_nonblessed);

    for my $name (@xs_compati_bit_properties, @pp_bit_properties) {
        my $flag_name = 'P_' . uc($name);

        eval qq/
            sub $name {
                my \$enable = defined \$_[1] ? \$_[1] : 1;

                if (\$enable) {
                    \$_[0]->{PROPS}->[$flag_name] = 1;
                }
                else {
                    \$_[0]->{PROPS}->[$flag_name] = 0;
                }

                \$_[0];
            }

            sub get_$name {
                \$_[0]->{PROPS}->[$flag_name] ? 1 : '';
            }
        /;
    }
}

# Functions

my %encode_allow_method
     = map {($_ => 1)} qw/self_encode escape_slash as_nonblessed/;
my %decode_allow_method
     = map {($_ => 1)} qw/allow_singlequote relaxed/;

my $JSON; # cache

sub acl_encode_json ($) { # encode
    ($JSON ||= __PACKAGE__->new->ascii)->acl_encode(@_);
}

sub acl_decode_json { # decode
    ($JSON ||= __PACKAGE__->new->ascii)->acl_decode(@_);
}

# Methods

sub new {
    my $class = shift;
    my $self  = {
        max_depth   => 512,
        FLAGS       => 0,
        fallback      => sub { encode_error('Invalid value. JSON can only reference.') },
    };

    bless $self, $class;
}

sub acl_encode {
    return $_[0]->_acl_encode_json($_[1]);
}

sub acl_decode {
    return $_[0]->_acl_decode_json($_[1], 0x00000000);
}

# etc

sub max_depth {
    my $max  = defined $_[1] ? $_[1] : 0x80000000;
    $_[0]->{max_depth} = $max;
    $_[0];
}

sub get_max_depth { $_[0]->{max_depth}; }

###############################

###
### Perl => JSON
###

{ # Convert
    my $max_depth;
    my $ascii;

    my $escape_slash;

    my $depth;

    sub _acl_encode_json {
        my $self = shift;
        my $obj  = shift;

        $depth        = 0;

        ($max_depth) = @{$self}{qw/max_depth/};

        encode_error("hash- or arrayref expected (not a simple scalar)")
             if(!ref $obj);

        my $str  = $self->object_to_json($obj);

        return $str;
    }

    sub object_to_json {
        my ($self, $obj) = @_;
        my $type = ref($obj);

        if($type eq 'HASH'){
            return $self->hash_to_json($obj);
        }
        elsif($type eq 'ARRAY'){
            return $self->array_to_json($obj);
        }
        else{
            return $self->value_to_json($obj);
        }
    }

    sub hash_to_json {
        my ($self, $obj) = @_;
        my ($k,$v);
        my %res;

        encode_error("json text or perl structure exceeds maximum nesting level (max_depth set too low?)")
                                         if (++$depth > $max_depth);

        my ($pre, $post) =  ('', '');
        my $del = ':';

        if ( my $tie_class = tied %$obj ) {
            if ( $tie_class->can('TIEHASH') ) {
                $tie_class =~ s/=.+$//;
                tie %res, $tie_class;
            }
        }

        # In the old Perl verions, tied hashes in bool context didn't work.
        # So, we can't use such a way (%res ? a : b)
        my $has;

        for my $k (keys %$obj) {
            my $v = $obj->{$k};
            $res{$k} = $self->object_to_json($v) || $self->value_to_json($v);
            $has = 1 unless ( $has );
        }

        --$depth;

        return '{'
                   . ( $has ? join(",$pre", map {
                                                string_to_json($self, $_) . $del . $res{$_} # key : value
                                            } _sort( $self, \%res )
                             )
                           : ''
                     )
             . '}';
    }

    sub array_to_json {
        my ($self, $obj) = @_;
        my @res;

        encode_error("json text or perl structure exceeds maximum nesting level (max_depth set too low?)")
                                         if (++$depth > $max_depth);

        my ($pre, $post) =  ('', '');

        if (my $tie_class = tied @$obj) {
            if ( $tie_class->can('TIEARRAY') ) {
                $tie_class =~ s/=.+$//;
                tie @res, $tie_class;
            }
        }

        for my $v (@$obj){
            push @res, $self->object_to_json($v) || $self->value_to_json($v);
        }

        --$depth;

        return '[' . ( @res ? $pre : '' ) . ( @res ? join( ",$pre", @res ) . $post : '' ) . ']';
    }

    sub value_to_json {
        my ($self, $value) = @_;

        return 'null' if(!defined $value);

        # Return numbers as-is
        return $value if (($value * 1) eq $value);

        my $type = ref($value);

        if(!$type){
            return string_to_json($self, $value);
        }
        elsif( blessed($value) and  $value->isa('acl::ACL_JSON::Boolean') ){
            return $$value == 1 ? 'true' : 'false';
        }
        else {
          return 'null';
        }

        return $value;
    }

    my %esc = (
        "\n" => '\n',
        "\r" => '\r',
        "\t" => '\t',
        "\f" => '\f',
        "\b" => '\b',
        "\"" => '\"',
        "\\" => '\\\\',
        "\'" => '\\\'',
    );

    sub string_to_json {
        my ($self, $arg) = @_;

        $arg =~ s/([\x22\x5c\n\r\t\f\b])/$esc{$1}/g;
        $arg =~ s/\//\\\//g if ($escape_slash);
        $arg =~ s/([\x00-\x08\x0b\x0e-\x1f])/'\\u00' . unpack('H2', $1)/eg;

        $arg = _encode_ascii($arg);

        return '"' . $arg . '"';
    }

    sub encode_error {
        my $error  = shift;
        die "$error";
    }

    sub _sort {
        my ($self, $res) = @_;
        keys %$res;
    }

} # Convert

sub _encode_ascii {
    join('',
        map {
            $_ <= 127 ?
                chr($_) :
            $_ <= 65535 ?
                sprintf('\u%04x', $_) : sprintf('\u%x\u%x', _encode_surrogates($_));
        } unpack('U*', $_[0])
    );
}

#
# JSON => Perl
#

my $max_intsize;

BEGIN {
    my $checkint = 1111;
    for my $d (5..30) {
        $checkint .= 1;
        my $int   = eval qq| $checkint |;
        if ($int =~ /[eE]/) {
            $max_intsize = $d - 1;
            last;
        }
    }
}

{ # PARSE 

    my %escapes = ( #  by Jeremy Muhlich <jmuhlich [at] bitflood.org>
        b    => "\x8",
        t    => "\x9",
        n    => "\xA",
        f    => "\xC",
        r    => "\xD",
        '\\' => '\\',
        '"'  => '"',
        '/'  => '/',
    );

    my $text; # json data
    my $at;   # offset
    my $ch;   # 1chracter
    my $len;  # text length
    # INTERNAL
    my $depth;          # nest counter
    # FLAGS
    my $max_depth;      # max nest nubmer of objects and arrays
    my $relaxed;
    my $cb_object;
    my $cb_sk_object;

    my $F_HOOK;

    my $singlequote;    # loosely quoting

    sub _acl_decode_json {
        my ($self, $opt); # $opt is an effective flag during this decode_json.

        ($self, $text, $opt) = @_;

        ($at, $ch, $depth) = (0, '', 0);

        if ( !defined $text or ref $text ) {
            decode_error("malformed JSON string, neither array, object, number, string or atom");
        }

        my $idx = $self->{PROPS};

        utf8::upgrade( $text );

        $len = length $text;

        ($max_depth, $cb_object, $cb_sk_object, $F_HOOK)
             = @{$self}{qw/max_depth cb_object cb_sk_object F_HOOK/};

        white(); # remove head white space

        my $valid_start = defined $ch; # Is there a first character for JSON structure?

        my $result = value();

        decode_error("malformed JSON string, neither array, object, number, string or atom") unless $valid_start;

        if ( !ref $result ) {
                decode_error(
                'JSON text must be an object or array (but found number, string, true, false or null'
                       . ')', 1);
        }

        if ( $len < $at ) { # we won't arrive here.
          die('something wrong.');
        }

        my $consumed = defined $ch ? $at - 1 : $at; # consumed JSON text length

        white(); # remove tail white space

        if ( $ch ) {
            decode_error("garbage after JSON object");
        }

        $result;
    }

    sub next_chr {
        return $ch = undef if($at >= $len);
        $ch = substr($text, $at++, 1);
    }

    sub value {
        white();
        return          if(!defined $ch);
        return object() if($ch eq '{');
        return array()  if($ch eq '[');
        return string() if($ch eq '"' or ($singlequote and $ch eq "'"));
        return number() if($ch =~ /[0-9]/ or $ch eq '-');
        return word();
    }

    sub string {
        my ($i, $s, $t, $u);
        my $is_utf8;

        $s = ''; # basically UTF8 flag on

        if($ch eq '"' or ($singlequote and $ch eq "'")){
            my $boundChar = $ch if ($singlequote);

            OUTER: while( defined(next_chr()) ){

                if((!$singlequote and $ch eq '"') or ($singlequote and $ch eq $boundChar)){
                    next_chr();

                    utf8::decode($s) if($is_utf8);

                    return $s;
                }
                elsif($ch eq '\\'){
                    next_chr();
                    if(exists $escapes{$ch}){
                        $s .= $escapes{$ch};
                    }
                    else{
                        $at -= 2;
                        decode_error('illegal backslash escape sequence in string');
                        $s .= $ch;
                    }
                }
                else{
                    if ($ch =~ /[\x00-\x1f\x22\x5c]/)  { # '/' ok
                        $at--;
                        decode_error('invalid character encountered while parsing JSON string');
                    }

                    $s .= $ch;
                }
            }
        }

        decode_error("unexpected end of string while parsing JSON string");
    }

    sub white {
        while( defined $ch  ){
            if($ch le ' '){
                next_chr();
            }
            elsif($ch eq '/'){
                next_chr();
                if(defined $ch and $ch eq '/'){
                    1 while(defined(next_chr()) and $ch ne "\n" and $ch ne "\r");
                }
                elsif(defined $ch and $ch eq '*'){
                    next_chr();
                    while(1){
                        if(defined $ch){
                            if($ch eq '*'){
                                if(defined(next_chr()) and $ch eq '/'){
                                    next_chr();
                                    last;
                                }
                            }
                            else{
                                next_chr();
                            }
                        }
                        else{
                            decode_error("Unterminated comment");
                        }
                    }
                    next;
                }
                else{
                    $at--;
                    decode_error("malformed JSON string, neither array, object, number, string or atom");
                }
            }
            else{
                if ($relaxed and $ch eq '#') { # correctly?
                    pos($text) = $at;
                    $text =~ /\G([^\n]*(?:\r\n|\r|\n|$))/g;
                    $at = pos($text);
                    next_chr;
                    next;
                }

                last;
            }
        }
    }

    sub array {
        my $a  = [];

        decode_error('json text or perl structure exceeds maximum nesting level (max_depth set too low?)')
                                                    if (++$depth > $max_depth);

        next_chr();
        white();

        if(defined $ch and $ch eq ']'){
            --$depth;
            next_chr();
            return $a;
        }
        else {
            while(defined($ch)){
                push @$a, value();

                white();

                if (!defined $ch) {
                    last;
                }

                if($ch eq ']'){
                    --$depth;
                    next_chr();
                    return $a;
                }

                if($ch ne ','){
                    last;
                }

                next_chr();
                white();

                if ($relaxed and $ch eq ']') {
                    --$depth;
                    next_chr();
                    return $a;
                }
            }
        }

        decode_error(", or ] expected while parsing array");
    }

    sub object {
        my $o = {};
        my $k;

        decode_error('json text or perl structure exceeds maximum nesting level (max_depth set too low?)')
                                                if (++$depth > $max_depth);
        next_chr();
        white();

        if(defined $ch and $ch eq '}'){
            --$depth;
            next_chr();
            if ($F_HOOK) {
                return _json_object_hook($o);
            }
            return $o;
        }
        else {
            while (defined $ch) {
                $k = string();
                white();

                if(!defined $ch or $ch ne ':'){
                    $at--;
                    decode_error("':' expected");
                }

                next_chr();
                $o->{$k} = value();
                white();

                last if (!defined $ch);

                if($ch eq '}'){
                    --$depth;
                    next_chr();
                    if ($F_HOOK) {
                        return _json_object_hook($o);
                    }
                    return $o;
                }

                if($ch ne ','){
                    last;
                }

                next_chr();
                white();

                if ($relaxed and $ch eq '}') {
                    --$depth;
                    next_chr();
                    if ($F_HOOK) {
                        return _json_object_hook($o);
                    }
                    return $o;
                }
            }
        }

        $at--;
        decode_error(", or } expected while parsing object/hash");
    }

    sub word {
        my $word =  substr($text,$at-1,4);

        if($word eq 'true'){
            $at += 3;
            next_chr;
            return $acl::ACL_JSON::true;
        }
        elsif($word eq 'null'){
            $at += 3;
            next_chr;
            return undef;
        }
        elsif($word eq 'fals'){
            $at += 3;
            if(substr($text,$at,1) eq 'e'){
                $at++;
                next_chr;
                return $acl::ACL_JSON::false;
            }
        }

        $at--; # for decode_error report

        decode_error("'null' expected")  if ($word =~ /^n/);
        decode_error("'true' expected")  if ($word =~ /^t/);
        decode_error("'false' expected") if ($word =~ /^f/);
        decode_error("malformed JSON string, neither array, object, number, string or atom");
    }

    sub number {
        my $n    = '';
        my $v;

        # According to RFC4627, hex or oct digts are invalid.
        if($ch eq '0'){
            my $peek = substr($text,$at,1);
            my $hex  = $peek =~ /[xX]/; # 0 or 1

            if($hex){
                decode_error("malformed number (leading zero must not be followed by another digit)");
                ($n) = ( substr($text, $at+1) =~ /^([0-9a-fA-F]+)/);
            }
            else{ # oct
                ($n) = ( substr($text, $at) =~ /^([0-7]+)/);
                if (defined $n and length $n > 1) {
                    decode_error("malformed number (leading zero must not be followed by another digit)");
                }
            }

            if(defined $n and length($n)){
                if (!$hex and length($n) == 1) {
                   decode_error("malformed number (leading zero must not be followed by another digit)");
                }
                $at += length($n) + $hex;
                next_chr;
                return $hex ? hex($n) : oct($n);
            }
        }

        if($ch eq '-'){
            $n = '-';
            next_chr;
            if (!defined $ch or $ch !~ /\d/) {
                decode_error("malformed number (no digits after initial minus)");
            }
        }

        while(defined $ch and $ch =~ /\d/){
            $n .= $ch;
            next_chr;
        }

        if(defined $ch and $ch eq '.'){
            $n .= '.';

            next_chr;
            if (!defined $ch or $ch !~ /\d/) {
                decode_error("malformed number (no digits after decimal point)");
            }
            else {
                $n .= $ch;
            }

            while(defined(next_chr) and $ch =~ /\d/){
                $n .= $ch;
            }
        }

        if(defined $ch and ($ch eq 'e' or $ch eq 'E')){
            $n .= $ch;
            next_chr;

            if(defined($ch) and ($ch eq '+' or $ch eq '-')){
                $n .= $ch;
                next_chr;
                if (!defined $ch or $ch =~ /\D/) {
                    decode_error("malformed number (no digits after exp sign)");
                }
                $n .= $ch;
            }
            elsif(defined($ch) and $ch =~ /\d/){
                $n .= $ch;
            }
            else {
                decode_error("malformed number (no digits after exp sign)");
            }

            while(defined(next_chr) and $ch =~ /\d/){
                $n .= $ch;
            }
        }

        $v .= $n;

        if ($v !~ /[.eE]/ and length $v > $max_intsize) {
            return "$v";
        }

        return 0+$v;
    }

    sub decode_error {
        my $error  = shift;
        my $no_rep = shift;
        my $str    = defined $text ? substr($text, $at) : '';
        my $mess   = '';
        my $type   = 'U*';

        for my $c ( unpack( $type, $str ) ) { # emulate pv_uni_display() ?
            $mess .=  $c == 0x07 ? '\a'
                    : $c == 0x09 ? '\t'
                    : $c == 0x0a ? '\n'
                    : $c == 0x0d ? '\r'
                    : $c == 0x0c ? '\f'
                    : $c <  0x20 ? sprintf('\x{%x}', $c)
                    : $c == 0x5c ? '\\\\'
                    : $c <  0x80 ? chr($c)
                    : sprintf('\x{%x}', $c)
                    ;
            if ( length $mess >= 20 ) {
                $mess .= '...';
                last;
            }
        }

        unless ( length $mess ) {
            $mess = '(end of string)';
        }

        die (
            $no_rep ? "$error" : "$error, at character offset $at (before \"$mess\")"
        );
    }

    sub _json_object_hook {
        my $o    = $_[0];
        my @ks = keys %{$o};

        if ( $cb_sk_object and @ks == 1 and exists $cb_sk_object->{ $ks[0] } and ref $cb_sk_object->{ $ks[0] } ) {
            my @val = $cb_sk_object->{ $ks[0] }->( $o->{$ks[0]} );
            if (@val == 1) {
                return $val[0];
            }
        }

        my @val = $cb_object->($o) if ($cb_object);
        if (@val == 0 or @val > 1) {
            return $o;
        }
        else {
            return $val[0];
        }
    }

} # PARSE


###############################
# Utilities
#

BEGIN {
    eval 'sub UNIVERSAL::a_sub_not_likely_to_be_here { ref($_[0]) }';
    *acl::ACL_JSON::blessed = sub {
        local($@, $SIG{__DIE__}, $SIG{__WARN__});
        ref($_[0]) ? eval { $_[0]->a_sub_not_likely_to_be_here } : undef;
    };
}


# shamely copied and modified from JSON::XS code.

$acl::ACL_JSON::true  = do { bless \(my $dummy = 1), "acl::ACL_JSON::Boolean" };
$acl::ACL_JSON::false = do { bless \(my $dummy = 0), "acl::ACL_JSON::Boolean" };

sub is_bool { defined $_[0] and UNIVERSAL::isa($_[0], "acl::ACL_JSON::Boolean"); }

sub true  { $acl::ACL_JSON::true  }
sub false { $acl::ACL_JSON::false }
sub null  { undef; }

1;
__END__
=pod

=head1 SYNOPSIS

 use acl::ACL_JSON;

 # exported functions, they die on error

 $ascii_encoded_json_text = acl_encode_json $perl_hash_or_arrayref;
 $perl_hash_or_arrayref  = acl_decode_json $ascii_encoded_json_text;

=head1 FUNCTIONS

Basically, check L<JSON> or L<JSON::XS>.

=head2 acl_encode_json

    $json_text = acl_encode_json $perl_scalar

=head2 acl_decode_json

    $perl_scalar = acl_decode_json $json_text

=head2 acl::ACL_JSON::true

Returns JSON true value which is blessed object.
It C<isa> acl::ACL_JSON::Boolean object.

=head2 acl::ACL_JSON::false

Returns JSON false value which is blessed object.
It C<isa> acl::ACL_JSON::Boolean object.

=head2 acl::ACL_JSON::null

Returns C<undef>.

=head1 METHODS

Basically, check to L<JSON> or L<JSON::XS>.

=head2 new

    $json = new acl::ACL_JSON

Rturns a new acl::ACL_JSON object that can be used to de/encode ascii JSON strings.

=head2 relaxed

    $json = $json->relaxed([$enable])
    
    $enabled = $json->get_relaxed

=head2 allow_unknown

    $json = $json->allow_unknown ([$enable])
    
    $enabled = $json->get_allow_unknown

=head2 max_depth

    $json = $json->max_depth([$maximum_nesting_depth])
    
    $max_depth = $json->get_max_depth

Sets the maximum nesting level (default C<512>) accepted while encoding
or decoding. If a higher nesting level is detected in JSON text or a Perl
data structure, then the encoder and decoder will stop and croak at that
point.

Nesting level is defined by number of hash- or arrayrefs that the encoder
needs to traverse to reach a given point or the number of C<{> or C<[>
characters without their matching closing parenthesis crossed to reach a
given character in a string.

If no argument is given, the highest possible setting will be used, which
is rarely useful.

See L<JSON::XS/SSECURITY CONSIDERATIONS> for more info on why this is useful.

When a large value (100 or more) was set and it de/encodes a deep nested object/text,
it may raise a warning 'Deep recursion on subroutin' at the perl runtime phase.

=head2 acl_encode

    $json_text = $json->acl_encode($perl_scalar)

=head2 acl_decode

    $perl_scalar = $json->acl_decode($json_text)

=head1 acl::ACL_JSON OWN METHODS

=head2 allow_singlequote

    $json = $json->allow_singlequote([$enable])

If C<$enable> is true (or missing), then C<decode> will accept
JSON strings quoted by single quotations that are invalid JSON
format.

    $json->allow_singlequote->decode({"foo":'bar'});
    $json->allow_singlequote->decode({'foo':"bar"});
    $json->allow_singlequote->decode({'foo':'bar'});

As same as the C<relaxed> option, this option may be used to parse
application-specific files written by humans.

=head2 escape_slash

    $json = $json->escape_slash([$enable])

According to JSON Grammar, I<slash> (U+002F) is escaped. But default
acl::ACL_JSON (as same as JSON::XS) encodes strings without escaping slash.

If C<$enable> is true (or missing), then C<encode> will escape slashes.

=head1 SEE ALSO

Most of the document is copied and modified from the JSON::PP doc.

L<JSON::PP>

RFC4627 (L<http://www.ietf.org/rfc/rfc4627.txt>)

=cut
