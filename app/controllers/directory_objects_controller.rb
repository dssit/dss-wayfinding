class DirectoryObjectsController < ApplicationController
  before_action :set_origin
  before_filter :require_login, except: [:index, :show, :search, :unroutable]
  before_filter :authenticate, except: [:index, :show, :search, :unroutable]
  filter_access_to :all

  respond_to :html, :json

  # GET /directory_objects
  def index
    @type = params[:type]

    if params[:type] == "Person"
      @directory_objects = Person.all.order(:last)
      @scrubber_categories = ("A".."Z").to_a
    elsif params[:type] == "Department"
      @directory_objects = Department.all.order(:title)
      @scrubber_categories = ("A".."Z").to_a
    elsif params[:type] == "Event"
      @directory_objects = Event.all.order(:title)
      @scrubber_categories = []
    elsif params[:type] == "Room"
      @directory_objects = Room.all.order(:room_number)
      @scrubber_categories = ['L',1,2,3,4,5]
    else
      # Unsupported behavior
      @directory_objects = []
      @scrubber_categories = []
    end

    @directory_objects = @directory_objects.uniq
  end

  def create
    type = params[:type].singularize.capitalize
    new_data = modify_with params, type

    logger.info Authorization.current_user.loginid.to_s + " created directory_object id: " + @object.id.to_s + " type: " + type

    if @object.update new_data
      respond_to do |format|
        format.json { render json: @object }
      end
    else
      respond_with_error("Error creating " + type + ".")
    end
  end

  def update
    type = params[:type].singularize.capitalize
    new_data = modify_with params, type

    logger.info Authorization.current_user.loginid.to_s + " updated directory_object id: " + @object.id.to_s + " type: " + type

    if @object.update new_data
      respond_to do |format|
        format.json { render json: @object }
      end
    else
      respond_with_error("Error saving " + type + ".")
    end
  end

  def destroy
    if params[:id].present?
      # Find existing object
      @object = DirectoryObject.find(params[:id])
    end
    if @object.present? and @object.type != 'Room'

      logger.info Authorization.current_user.loginid.to_s + " deleted directory_object id: " + @object.id.to_s + " type: " + params[:type].singularize.capitalize

      @object.destroy
      respond_to do |format|
        format.json {render json: { message: "Object deleted successfully", id: @object.id }, status: 302 }
      end
    else
      respond_to do |format|
        format.json {render json: { message: "Error deleting directory object" }, status: 405 }
      end
    end
  end

  # POST /directory/search
  def search
    if params[:q] && params[:q].length > 0
      @query = params[:q]
      objects = DirectoryObject.arel_table

      query_objs = params[:q].split(/\s+/).map { |q|
        "%#{q}%"
      }
      query_objs.push("%#{params[:q]}%")

      query = query_objs.reduce("") { |qry,obj|
        if ! qry.is_a?(Arel::Nodes::Grouping)
            new_qry = objects[:first].matches(obj)
        else
            new_qry = qry.or(objects[:first].matches(obj))
        end

        new_qry.or(objects[:last].matches(obj))
           .or(objects[:title].matches(obj))
           .or(objects[:email].matches(obj))
           .or(objects[:name].matches(obj))
           .or(objects[:room_number].matches(obj))
      }

      @directory_objects = DirectoryObject.where(query)

      @directory_objects = @directory_objects.uniq

      # Remove special characters
      clean_query = params[:q].downcase.gsub(/[^0-9A-Za-z\s]/, '')

      terms_list = clean_query.strip.split(/\s+/)

      terms_list.each do |term|
        term_log = SearchTermLog.where(term: term).first_or_create
        term_log.count = term_log.count + 1
        term_log.save
      end

      # No results were found, log the query
      if @directory_objects.first == nil
        UnmatchedQueryLog.where(query: clean_query).first_or_create
      end

      respond_to do |format|
        format.json
        format.html
      end
    end
  end

  def unroutable
    if ! params[:from] || ! params[:to]
      head 405, content_type: "text/html"
    end

    unroutable_route = UnroutableLog.where(unroutable_params).first_or_create

    if unroutable_route
        unroutable_route.hits ? unroutable_route.hits += 1 : unroutable_route.hits = 1
        unroutable_route.save
    end

    head :ok, content_type: "text/html"
  end

  # GET /directory_objects/1
  # GET /room/1
  # GET /start/R0070/end/R2169
  # GET /start/R0070/directory/1234
  def show
    @directory_object = DirectoryObject.where(room_number: params[:number]).first if params[:number]
    @directory_object = DirectoryObject.find(params[:id]) if params[:id] && @directory_object.nil?

    respond_with @directory_object
  end

  private

  #
  # get_object
  #
  #     Generic function for creating or getting a directory_object, given
  #     parameters.
  #
  #     Arguments:
  #         params: (object) GET/POST parameters. Generally, POST parameters.
  #         type: (string) Type of the directory object being retrieved
  #
  #     Returns: A new or existing object of the appropriate type, or nil if the
  #         given type is not a valid type.
  #
  
  def get_object(params, type)
    # Room or existing Person or Department
    return DirectoryObject.find_by(id: params[:id])  if ! params[:id].nil?

    # New Person or Department
    case type
    when 'Person'
      return Person.new
    when 'Department'
      return Department.new
    end

    # Unidentified object
    return nil
  end


  #
  # respond_with_error
  #
  #     Generates a server response (status 405) with the given error message.
  #
  #     Arguments:
  #         mesg: (string) The error message to be included in the server
  #             response.
  #
  #     Side-effects: Generates a server response with status 405
  #

  def respond_with_error(mesg)
    respond_to do |format|
      format.json { render json: { message: mesg }, status: 405 }
    end

    return false
  end


  #
  # modify_with
  #
  #     Generic function for creating and updating directory objects. Accepts
  #     parameters defining the directory object to be created or updated and
  #     does the appropriate action.
  #
  
  def modify_with(params, type)
    @object = get_object(params, type)
    return respond_with_error("Error identifying type of object")  if !@object.present?

    # No need for additional sanity checks as we already know that we're working
    # with an existing type (see above)
    new_data = send('modify_' + type, params)

    # Don't continue if the new data aren't valid for some reason (e.g., 
    # invalid phone number) -- modify_* functions return false for invalid data
    return false if ! new_data 

    return new_data 
  end

  #
  # modify_Room
  #
  #     Builds object necessary for updating room records.
  #

  def modify_Room(params)
    return params.permit(:name)
  end

  #
  # modify_Person
  #
  #     Builds object necessary for updating/creating person records.
  #

  def modify_Person(params)
    if params[:first].blank? || params[:last].blank?
        return respond_with_error("Error: first and last names must both be supplied")
    end

    # No require on :first and :last because require only accepts one parameter,
    # and they're already checked above
    person = params.permit(:first, :last, :email, :phone)
    person[:department] = params[:department_id].blank? ? nil : Department.find(params[:department_id])
    person[:rooms] = params[:room_ids].map { |room| Room.find(room) } unless params[:room_ids].nil?
    return respond_with_error("Error: Invalid phone number")  if !valid_number(params[:phone])

    return person
  end


  #
  # modify_Department
  #
  #     Builds object necessary for updating/creating department records.
  #

  def modify_Department(params)
    return respond_with_error("Department must have title.")  if params[:title].blank?

    department = params.permit(:title)
    department[:room] = params[:room_number].blank? ? nil : Room.find_by(room_number: params[:room_number].rjust(4,'0'))

    return department
  end

  #
  # room
  #
  #     Normalizes input for room numbers
  #

  def normalize_room(number)
    return nil if number.nil?
    number.slice!(0) if number[0].upcase == "R"
    return number.to_s.rjust(4, '0').prepend("R")
  end

  #
  # valid_number
  #
  #     Tests whether or not a phone number is a valid five-, seven-, or
  #     ten-digit phone number. Compares given number to a version that strips
  #     everything but valid non-numeric characters.
  #
  #     Arguments:
  #         phone: (string) Phone number to test
  #
  #     Returns: Whether or not the given string is a valid phone number.
  #

  def valid_number(phone)
    phone.strip!
    trimmed = phone.gsub(/[^\dx]/, "").gsub(/x\d*/, "")
    trimmedLength = trimmed.length;

    return false  if trimmedLength != 5 && trimmedLength != 7 && trimmedLength != 10 && trimmedLength != 11
    return true  if phone.gsub(/[^\d\+x)( \-]/, "") == phone

    return false
  end

  #
  # set_origin
  #
  #     Called before ev'rything else. Sets @origin and @dest for views, if
  #     applicable.
  #
  
  def set_origin
    # Prefer url-specified start locations over set ones when the URL is of
    # format /start/.../end/...
    @origin = normalize_room(params[:start_loc]) ||
               cookies[:origin] || cookies[:start_location]
    @dest = normalize_room(params[:end_loc])

    unless @origin
      logger.error "An instance of Wayfinding had a page loaded without an origin set. IP: #{request.remote_ip}"
    end
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def directory_object_params
    params.require(:directory_object).permit(:title, :time, :link, :first, :last, :email, :phone, :name, :room_number, :is_bathroom, :rss_feed, :type, :room_id)
  end

  def unroutable_params
    params.permit(:from, :to)
  end
end
