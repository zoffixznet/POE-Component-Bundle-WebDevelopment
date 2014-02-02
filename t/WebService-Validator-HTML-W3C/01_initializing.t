
use Test::More tests => 8;
BEGIN {
    use_ok('XML::XPath');
    use_ok('Carp');
    use_ok('WebService::Validator::HTML::W3C');
    use_ok('POE');
    use_ok('POE::Wheel::Run');
    use_ok('POE::Filter::Reference');
    use_ok('POE::Filter::Line');
    use_ok('POE::Component::WebService::Validator::HTML::W3C');
};
