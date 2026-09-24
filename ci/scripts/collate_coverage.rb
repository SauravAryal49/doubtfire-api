# Runs inside the OnTrack image (see merge-coverage.sh).
require 'simplecov'
require 'simplecov-cobertura'

files = Dir['/tmp/*.resultset.json']
abort 'No coverage result sets found' if files.empty?

SimpleCov.collate files, 'rails' do
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::CoberturaFormatter
  ])
end
