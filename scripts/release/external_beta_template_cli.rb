#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "external_beta_templates"

module DeskSetupExternalBetaTemplateCLI
  class CLIError < StandardError; end

  module_function

  def fail_cli!(message)
    raise CLIError, message
  end

  def exact_string(value, label)
    unless value.is_a?(String) && !value.empty? && value.valid_encoding? &&
           !value.match?(/[\0\r\n]/)
      fail_cli!("#{label} is not a single-line string")
    end
    value
  end

  def run(argv)
    options = {}
    set_once = lambda do |name, item|
      fail_cli!("template option is repeated") if options.key?(name)
      options[name] = item
    end
    parser = OptionParser.new do |value|
      value.banner = "Usage: external_beta_template_cli.rb [options]"
      value.on("--kind KIND") { |item| set_once.call(:kind, item) }
      value.on("--report-code CODE") { |item| set_once.call(:report_code, item) }
      value.on("--coverage-role ROLE") { |item| set_once.call(:coverage_role, item) }
      value.on("--sonoma-report-code CODE") { |item| set_once.call(:sonoma_report_code, item) }
    end
    parser.require_exact = true
    parser.parse!(argv)
    fail_cli!("unexpected arguments") unless argv.empty?
    fail_cli!("template kind is missing") unless options.key?(:kind)
    kind = exact_string(options.fetch(:kind), "template kind")
    fail_cli!("template kind is invalid") unless DeskSetupExternalBetaTemplates::TEMPLATE_KINDS.include?(kind)

    template = if kind.start_with?("candidate-inventory-")
                 fail_cli!("template options differ for this kind") unless options.keys == [:kind]
                 DeskSetupExternalBetaTemplates.inventory(kind)
               elsif kind.start_with?("predecessor-lineage-")
                 fail_cli!("template options differ for this kind") unless options.keys == [:kind]
                 DeskSetupExternalBetaTemplates.lineage(kind)
               elsif DeskSetupExternalBetaTemplates::REPORT_TEMPLATE_KINDS.include?(kind)
                 required = %i[kind report_code coverage_role]
                 fail_cli!("report template options are missing") unless
                   required.all? { |name| options.key?(name) }
                 fail_cli!("template options differ for this kind") unless options.keys.sort == required.sort
                 report_code = exact_string(options.fetch(:report_code), "template report code")
                 coverage_role = exact_string(options.fetch(:coverage_role), "template coverage role")
                 fail_cli!("template report code is invalid") unless
                   DeskSetupExternalBetaTemplates::REPORT_CODES.include?(report_code)
                 fail_cli!("template coverage role is invalid") unless
                   DeskSetupExternalBetaTemplates::COVERAGE_ROLES.include?(coverage_role)
                 DeskSetupExternalBetaTemplates.report(kind, report_code, coverage_role)
               else
                 required = %i[kind sonoma_report_code]
                 fail_cli!("set template options are missing") unless
                   required.all? { |name| options.key?(name) }
                 fail_cli!("template options differ for this kind") unless options.keys.sort == required.sort
                 sonoma_report_code = exact_string(
                   options.fetch(:sonoma_report_code),
                   "template Sonoma report code"
                 )
                 fail_cli!("template Sonoma report code is invalid") unless
                   DeskSetupExternalBetaTemplates::REPORT_CODES.include?(sonoma_report_code)
                 DeskSetupExternalBetaTemplates.set(sonoma_report_code)
               end
    puts JSON.pretty_generate(template)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    DeskSetupExternalBetaTemplateCLI.run(ARGV)
  rescue DeskSetupExternalBetaTemplateCLI::CLIError => error
    warn "External beta template error: #{error.message}"
    exit 1
  rescue OptionParser::ParseError
    warn "External beta template error: invalid command line."
    exit 1
  rescue StandardError
    warn "External beta template error: generation failed safely."
    exit 1
  end
end
