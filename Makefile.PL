use inc::Module::Install;
name 'App-Mobijiro';
all_from 'lib/App/Mobijiro.pm';

requires 'AE';
requires 'AnyEvent::IRC::Client';
requires 'Data::Validate::URI';
requires 'Tatsumaki::HTTPClient';
requires 'URI';
requires 'Web::Scraper';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';
auto_set_repository;
auto_include;
WriteAll;
