class Vault
  constructor: (@name, @urls, options = {}) ->
    # Setup some internal variables.
    @objects = []
    @dirty_object_count = 0
    @save_error_count = 0
    @messages =
      notices: []
      warnings: []
      errors: []

    # This property is used to temporarily lock the vault during mutation methods.
    @locked = false

    # Create a date object which will be used to
    # generate unique IDs for new records.
    @date = new Date

    # Declare default options.
    @options =
      autoload: true
      after_load: ->
      id_attribute: "id"
      offline: false
      sub_collections: []

    # Merge default options with user-defined ones.
    for option, value of options
      @options[option] = value

    # Setup the vault for offline use.
    if @options.offline
      # Bind a cache routine to save data should the window be closed or url changed.
      $(window).unload =>
        @store()

    # Load the collection if configured to do so.
    if @options.autoload
      # Check the offline data store first, if configured to do so.
      if @options.offline
        if @load()
          if @dirty_object_count > 0
            # Offline data loaded and modifications found; keep existing data.
            @messages.notices.push "Found and using dirty offline data."

            # Detach the callback to after_load so that the call to the
            # vault constructor can complete/return, allowing any post-load code
            # to use the newly instantiated vault object as required.
            window.setTimeout @options.after_load, 100
          else
            # No modifications in offline data; reload fresh data.
            @messages.notices.push "No modifications found in offline data. Reloading..."

            if @urls.list?
              @reload(@options.after_load)
            else
              # Can't reload without a list url; use the offline data we've loaded.
              @messages.notices.push "List url not configured; using offline data instead."
            
              # Detach the callback to after_load so that the call to the
              # vault constructor can complete/return, allowing any post-load code
              # to use the newly instantiated vault object as required.
              window.setTimeout @options.after_load, 100
        else
          if navigator.onLine
            # Load failed, but we're connected; reload fresh data.
            @messages.warnings.push "Offline data load failed. Reloading..."
            
            if @urls.list?
              @reload(@options.after_load)
            else
              # Can't reload without a list url; use an empty dataset.
              @messages.warnings.push "List url not configured; using empty dataset instead."
            
              # Detach the callback to after_load so that the call to the
              # vault constructor can complete/return, allowing any post-load code
              # to use the newly instantiated vault object as required.
              window.setTimeout @options.after_load, 100
          else
            # Load failed and we're offline; use an empty dataset.
            @messages.warnings.push "Browser is offline and cannot reload; using empty dataset instead."
            
            # Detach the callback to after_load so that the call to the
            # vault constructor can complete/return, allowing any post-load code
            # to use the newly instantiated vault object as required.
            window.setTimeout @options.after_load, 100
      else
        # Not using offline data; reload fresh data.
        @messages.notices.push "Not configured for offline data. Reloading..."

        if @urls.list?
          @reload(@options.after_load)
        else
          # Can't reload without a list url; use an empty dataset.
          @messages.notices.push "List url not configured; using empty dataset instead."
            
          # Detach the callback to after_load so that the call to the
          # vault constructor can complete/return, allowing any post-load code
          # to use the newly instantiated vault object as required.
          window.setTimeout @options.after_load, 100
    
    # Create convenience attributes for sub-collections.
    for sub_collection in @options.sub_collections
      do (sub_collection) =>
        @[sub_collection] = {
          'find': (id) =>
            for object in @objects
              for sub_object in object[sub_collection]
                if sub_object[@options.id_attribute].toString() is id.toString()
                  return sub_object
              
            # Object with specified id couldn't be found.
            return false
        }

  # Iterate over non-deleted items in the collection.
  each: (logic) ->
    for object in @objects
      unless object.status == "deleted"
        logic object

  # Add a new item to the collection.
  add: (object) ->
    # Don't bother if the vault is locked.
    if @locked
      @messages.errors.push 'Cannot add, vault is locked.'
      return false

    # If the object has no id, generate a temporary one and add it to the object.
    unless object[@options.id_attribute]? and object[@options.id_attribute] isnt ''
      object[@options.id_attribute] = @date.getTime()

    # Extend the object with vault-specific variables and functions.
    @extend object,"new"

    # Add the object to the collection.
    @objects.push object

    # Increase the count of dirty objects.
    @dirty_object_count++

    # Store the collection.
    @store

    # Return the extended object.
    return object

  # Find an object in the collection using its id.
  find: (id) ->
    for object in @objects
      if object[@options.id_attribute].toString() is id.toString()
        return object

    # Object with specified id couldn't be found.
    return false

  # Update an existing item in the collection.
  update: (attributes, id) ->
    # Don't bother if the vault is locked.
    if @locked
      @messages.errors.push 'Cannot update, vault is locked.'
      return false
            
    # Get the id of the object from the attributes if it's not explicitly defined.
    id = attributes[@options.id_attribute] unless id?
            
    # Get the object; return if it's undefined.
    object = @find(id)
    unless object?
      @messages.errors.push 'Cannot update, object not found.'
      return false

    # Flag it as dirty.
    if object.status is "clean"
      object.status = "dirty"
      @dirty_object_count++
            
    # Merge in the updated attributes, if they're specified and defined on the object.
    if attributes?
      for attribute, value of attributes
        if object[attribute]?
          object[attribute] = value

    # Store the collection.
    @store

    # Update was successful.
    return true

  # Flag an object in the collection for deletion,
  # or if the object is new, remove it.
  delete: (id) ->
    # Don't bother if the vault is locked.
    if @locked
      @messages.errors.push 'Cannot delete, vault is locked.'
      return false

    for object, index in @objects
      if object[@options.id_attribute] == id
        switch object.status
          when "new"
            # New objects are special; we essentially want to
            # reverse the steps taken during the add operation.
            @objects.splice(index, 1)
            @dirty_object_count--
          when "clean"
            object.status = "deleted"
            @dirty_object_count++
          when "dirty"
            object.status = "deleted"

        # Store the collection.
        @store

        # Delete was successful.
        return true

    # Object not found.
    return false

  # Forcibly remove an object from the collection.
  destroy: (id) ->
    # Don't bother if the vault is locked.
    if @locked
      @messages.errors.push 'Cannot delete, vault is locked.'
      return false

    for object, index in @objects
      if object[@options.id_attribute] == id
        # Remove the object from the collection.
        @objects.splice(index, 1)

        # Reduce the dirty count if this object
        # was dirty, since we're no longer managing it.
        switch object.status
          when "new", "dirty"
            @dirty_object_count--

        # Store the collection.
        @store

        # Destroy was successful.
        return true

    # Object not found.
    return false

  # Write an object back to the server.
  save: (id, after_save = ->) ->
    # Don't bother if the vault is locked, we're offline or there's nothing to sync.
    if @locked
      @messages.errors.push 'Cannot save, vault is locked.'
      return after_save()
    else if not navigator.onLine
      @messages.errors.push 'Cannot save, navigator is offline.'
      return after_save()
    else if @dirty_object_count is 0
      @messages.errors.push 'Nothing to save.'
      return after_save()

    # Lock the vault until the save is complete.
    @locked = true

    # Find the object using the specified id.
    object = @find(id)

    # Package up the object to be sent to the server.
    packaged_object = {}
    packaged_object[@name] = JSON.stringify @strip object

    switch object.status
      when "deleted"
        $.ajax
          type: 'DELETE'
          url: @urls.delete
          data: packaged_object
          fixture: (settings) ->
            return true
          success: (data) =>
            # Forcibly remove the deleted object from the collection.
            for vault_object, index in @objects
              if vault_object.id == object.id
                @objects.splice(index, 1)
                @dirty_object_count--
          error: =>
            @messages.errors.push 'Failed to delete.'
          complete: =>
            # Store the collection, unlock the vault, and execute the callback method.
            @store
            @locked = false
            after_save()
          dataType: 'json'
      when "new"
        $.ajax
          type: 'POST'
          url: @urls.create
          data: packaged_object
          fixture: (settings) =>
            return {
              id: 123
              make: "Dodge",
              model: "Viper SRT-10",
              year: 2008}
          success: (data) =>
            # Unlock the vault prematurely so that we can update it.
            @locked = false

            # Update the object with the attributes sent from the server.
            object.update data, object.id

            object.status = "clean"
            @dirty_object_count--
          error: =>
            @messages.errors.push 'Failed to create.'
          complete: =>
            # Store the collection, unlock the vault, and execute the callback method.
            @store
            @locked = false
            after_save()
          dataType: 'json'
      when "dirty"
        $.ajax
          type: 'POST'
          url: @urls.update
          data: packaged_object
          fixture: (settings) ->
            return true
          success: (data) =>
            object.status = "clean"
            @dirty_object_count--
          error: =>
            @messages.errors.push 'Failed to update.'
          complete: =>
            # Store the collection, unlock the vault, and execute the callback method.
            @store
            @locked = false
            after_save()
          dataType: 'json'
  
  # Used to wipe out the in-memory object list with a fresh one from the server.
  reload: (after_load = ->) ->
    # Don't bother if the vault is locked or we're offline.
    if @locked
      @messages.errors.push 'Cannot reload, vault is locked.'
      return after_load()
    else if not navigator.onLine
      @messages.errors.push 'Cannot reload, navigator is offline.'
      return after_load()
    else if not @urls.list?
      @messages.errors.push 'Cannot reload, list url is not configured.'
      return after_load()

    # Lock the vault until the reload is complete.
    @locked = true

    $.ajax
      url: @urls.list
      dataType: 'json'
      success: (data) =>
        # Replace the list of in-memory objects with the new data.
        @objects = data

        # Extend the objects with vault-specific variables and functions.
        for object in @objects
          @extend object

        # Reset the count of dirty objects.
        @dirty_object_count = 0

        # Store the collection.
        @store

        # Call the callback function as the reload is complete.
        after_load()
      error: =>
        @messages.errors.push 'Failed to list.'

        # Call the callback function as the reload is complete (albeit unsuccessful).
        after_load()
      complete: =>
        # Unlock the vault as the reload is complete.
        @locked = false

  # Convenience method for saving and reloading in one shot.
  synchronize: (after_sync = ->) ->
    # Don't bother if we're offline.
    unless navigator.onLine
      @messages.errors.push 'Cannot synchronize, navigator is offline.'
      return after_sync()

    @save =>
      # Only reload the collection if there were no save errors.
      if @messages.errors.length is 0
        @reload(after_sync)
      else
        after_sync()

  # Load the collection from offline storage.
  load: ->
    # Don't bother if offline support is disabled.
    unless @options.offline
      return false

    # Try to load the collection.
    if localStorage.getItem(@name)
      @objects = $.parseJSON(localStorage.getItem @name)

      # Extend the loaded objects with vault-specific variables and functions.
      for object in @objects
        @extend object

      # Calculate the number of dirty objects.
      for object in @objects
        unless object.status is "clean"
          @dirty_object_count++
      
      return true
    else
      return false

  # Store the collection for offline use.
  store: ->
    # Don't bother if offline support is disabled.
    unless @options.offline
      return false

    # Store the collection.
    localStorage.setItem(@name, JSON.stringify(@objects))
    return true

  # Extend an object with vault-specific variables and functions.
  extend: (object, status) ->
    # Validate the status argument.
    if status?
      throw "Invalid status specified: cannot extend object." unless status in ['clean', 'dirty', 'new']
    
    # Add simple variables and methods.
    object.update = (attributes) =>
      @update(attributes, object.id)
    object.delete = =>
      @delete(object.id)
    object.destroy = =>
      @destroy(object.id)
    object.save = (after_save) =>
      @save(object.id, after_save)
    
    if status?
      # Status has been explicitly defined; force it on the object.
      object.status = status
    else
      # Default the object's status to clean if it doesn't exist.
      object.status = "clean" unless object.status?
    
    # Iterate through all of the sub-collections, and if present
    # extend them with some basic functionality.
    for sub_collection in @options.sub_collections
      do (sub_collection) =>
        if object[sub_collection]?
          # Find functionality.
          object[sub_collection].find = (id) =>
            for sub_collection_object in object[sub_collection]
              if sub_collection_object[@options.id_attribute].toString() is id.toString()
                return sub_collection_object
              
            # Object with specified id couldn't be found.
            return false
          
          # Add functionality.
          object[sub_collection].add = (sub_object) =>
            # Don't bother if the vault is locked.
            if @locked
              @messages.errors.push 'Cannot add sub-object, vault is locked.'
              return false
            
            # Set a status on the object.
            sub_object.status = "new"

            # If the sub-object has no id, generate a temporary one and add it to the sub-object.
            unless sub_object[@options.id_attribute]? and sub_object[@options.id_attribute] isnt ''
              sub_object[@options.id_attribute] = @date.getTime()
            
            # Add a delete method to the sub-object.
            sub_object.delete = =>
              object[sub_collection].delete(sub_object[@options.id_attribute])
            
            # Add an update method to the sub-object.
            sub_object.update = (attributes) =>
              object[sub_collection].update(attributes, sub_object[@options.id_attribute])

            # Add the object to the collection.
            object[sub_collection].push sub_object

            # If the root object was clean, flag it and increase the count of dirty objects.
            if object.status is "clean"
              object.status = "dirty"
              @dirty_object_count++

            # Store the collection.
            @store
            
            return sub_object
          
          # Delete functionality.
          object[sub_collection].delete = (id) =>
            # Don't bother if the vault is locked.
            if @locked
              @messages.errors.push 'Cannot delete sub-object, vault is locked.'
              return false
            
            # Remove the sub-object from its collection.
            for sub_object, index in object[sub_collection]
              if sub_object[@options.id_attribute] is id
                object[sub_collection].splice(index, 1)

            # If the root object was clean, flag it and increase the count of dirty objects.
            if object.status is "clean"
              object.status = "dirty"
              @dirty_object_count++

            # Store the collection.
            @store
          
          # Add a delete instance method for pre-existing objects.
          for sub_object, index in object[sub_collection]
            sub_object.delete = =>
              object[sub_collection].delete(sub_object[@options.id_attribute])
          
          # Update functionality.
          object[sub_collection].update = (attributes, id) =>
            # Don't bother if the vault is locked.
            if @locked
              @messages.errors.push 'Cannot update sub-object, vault is locked.'
              return false
            
            # Get the id of the sub-object from the attributes if it's not explicitly defined.
            id = attributes[@options.id_attribute] unless id?
            
            # Get the sub-object; return if it's undefined.
            sub_object = object[sub_collection].find(id)
            unless sub_object?
              @messages.errors.push 'Cannot update, sub-object not found.'
              return false

            # If the root object was clean, flag it and increase the count of dirty objects.
            if object.status is "clean"
              object.status = "dirty"
              @dirty_object_count++
            
            # Merge in the updated attributes, if they're specified and defined on the sub-object.
            if attributes?
              for attribute, value of attributes
                if sub_object[attribute]?
                  sub_object[attribute] = value
            
            # Store the collection.
            @store
          
          # Add an update instance method for pre-existing objects.
          for sub_object in object[sub_collection]
            do (sub_object) =>
              sub_object.update = (attributes) =>
                object[sub_collection].update(attributes, sub_object[@options.id_attribute])
      
    return object

  # Return a copy of an object with vault-specific variables and functions removed.
  strip: (object) ->
    # Clone the object so that we don't strip the original.
    object_clone = @clone object

    # Remove the temporary id given to new objects.
    if object_clone.status is "new"
      delete object_clone[@options.id_attribute]
    
    # Remove vault object methods.
    delete object_clone.status
    delete object_clone.update
    delete object_clone.delete
    delete object_clone.destroy
    delete object_clone.save
    
    # Iterate through all of the sub-collections, and if present
    # strip them of their extended functionality.
    for sub_collection in @options.sub_collections
      if object_clone[sub_collection]?
        # Remove the sub-collection's methods.
        delete object_clone[sub_collection].find
        delete object_clone[sub_collection].add
        delete object_clone[sub_collection].delete
        delete object_clone[sub_collection].update
        
        # Iterate through and remove the extended instances' methods.
        for sub_object in object_clone[sub_collection]
          if sub_object.status is "new"
            delete sub_object[@options.id_attribute]
          delete sub_object.status
          delete sub_object.delete
          delete sub_object.update
    return object_clone

  # Clone (deep copy) an object.
  clone: (object) ->
    unless object? and typeof object is 'object'
      return object

    new_instance = new object.constructor()

    for key of object
      new_instance[key] = @clone object[key]

    return new_instance

  # Attach the Vault class to the window so that it can be used by other scripts.
  window.Vault = this
