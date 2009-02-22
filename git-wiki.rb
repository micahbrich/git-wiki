#!/usr/bin/ruby

require 'rubygems'
require 'sinatra'
require 'grit'
require 'rdiscount'

module GitWiki
  class << self
    attr_accessor :homepage, :extension, :repository
  end
  @repository = Grit::Repo.new(ARGV[0] || File.expand_path('~/wiki'))
  @extension = ARGV[1] || '.markdown'
  @homepage = ARGV[2] || 'Home'
end

class Page
  def self.find_all
    return [] if repository.tree.contents.empty?
    GitWiki.repository.tree.contents.collect { |blob| new(blob) }
  end

  def self.find_or_create(name)
    path = name + GitWiki.extension
    blob = GitWiki.repository.tree/path
    new(blob || Grit::Blob.create(GitWiki.repository, :name => path))
  end

  def self.css_class_for(name)
    find_blob(name) ? "exists" : "unknown"
  end

  def self.repository
    GitWiki.repository || raise
  end

  def self.extension
    GitWiki.extension || raise
  end

  def initialize(blob)
    @blob = blob
  end

  def to_html
    RDiscount.new(wiki_link(content)).to_html
  end

  def to_s
    name
  end

  def new?
    @blob.id.nil?
  end

  def name
    @blob.name.gsub(/#{File.extname(@blob.name)}$/, '')
  end

  def content
    @blob.data
  end

  def update_content(new_content)
    return if new_content == content
    File.open(file_name, "w") { |f| f << new_content }
    add_to_index_and_commit!
  end

  private
    def add_to_index_and_commit!
      Dir.chdir(self.class.repository.working_dir) {
        self.class.repository.add(@blob.name)
      }
      self.class.repository.commit_index(commit_message)
    end

    def file_name
      File.join(self.class.repository.working_dir, name + self.class.extension)
    end

    def commit_message
      new? ? "Created #{name}" : "Updated #{name}"
    end

    def wiki_link(str)
      str.gsub(/([A-Z][a-z]+[A-Z][A-Za-z0-9]+)/) { |page|
        %Q{<a class="#{self.class.css_class_for(page)}"} +
          %Q{href="/#{page}">#{page}</a>}
      }
    end
end

before do
  content_type "text/html", :charset => "utf-8"
end

helpers do
  def title(title=nil)
    @title = title.to_s unless title.nil?
    @title
  end

  def list_item(page)
    %Q{<a class="page_name" href="/#{page}">#{page.name}</a>}
  end
end

get "/" do
  redirect "/" + GitWiki.homepage
end

get "/pages" do
  @pages = Page.find_all
  haml :list
end

get "/:page/edit" do
  @page = Page.find_or_create(params[:page])
  haml :edit
end

get "/:page" do
  @page = Page.find_or_create(params[:page])
  haml :show
end

post "/:page" do
  @page = Page.find_or_create(params[:page])
  @page.update_content(params[:body])
  redirect "/#{@page}"
end

__END__
@@ layout
!!!
%html
  %head
    %title= title
  %body
    %ul
      %li
        %a{ :href => "/#{GitWiki.homepage}" } Home
      %li
        %a{ :href => "/pages" } All pages
    #content= yield

@@ show
- title @page.name
#edit
  %a{:href => "/#{@page}/edit"} Edit this page
%h1= title
#content
  ~"#{@page.to_html}"

@@ edit
- title "Editing #{@page.name}"
%h1= title
%form{:method => 'POST', :action => "/#{@page}"}
  %p
    %textarea{:name => 'body', :rows => 30, :style => "width: 100%"}= @page.content
  %p
    %input.submit{:type => :submit, :value => "Save as the newest version"}
    or
    %a.cancel{:href=>"/#{@page}"} cancel

@@ list
- title "Listing pages"
%h1 All pages
- if @pages.empty?
  %p No pages found.
- else
  %ul#list
    - @pages.each do |page|
      %li= list_item(page)
