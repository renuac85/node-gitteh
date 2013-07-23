###
Omg gitteh is freakin' sweet! :)
###

{EventEmitter} = require "events"
async = require "async"
fs = require "fs"
_path = require "path"
args = require "./args"

# env = if process.env.npm_lifecycle_event is "test" then "Debug" else "Release"
env = "Release"
bindings = require "../build/#{env}/gitteh"

(require "segfault-handler").registerHandler() if env is "Debug"

{minOidLength, types, NativeRepository, NativeRemote} = bindings
args.minOidLength = minOidLength

Gitteh = module.exports = {}

_getPrivate = (obj) ->
	_getPrivate.lock++
	return obj._private
_getPrivate.lock = 0

_createPrivate = (obj) ->
	_priv = {}
	Object.defineProperty obj, "_private",
		enumerable: false
		configurable: false
		get: ->
			throw new Error "Bad request" if not _getPrivate.lock--
			return _priv
	return _priv

_wrapCallback = (orig, cb) ->
	return (err) ->
		return orig err if err?
		cb.apply null, Array.prototype.slice.call arguments, 1

_immutable = (obj, src) ->
	return o = {
		set: (name, target = name) ->
			if Array.isArray src[name]
				Object.defineProperty obj, target,
					get: () -> src[name].slice(0)
					configurable: false
					enumerable: true
				return o
			Object.defineProperty obj, target, 
				value: src[name]
				writable: false
				configurable: false
				enumerable: true
			return o
	}


Gitteh.Signature = class Signature
	###
	Contains the name/email/time for a :class:`gitteh::Commit` author/committer
	or :class:`gitteh::Tag` tagger.

	Signatures contain the following *immutable* properties:

	* **name**: *(String)*
	* **email**: *(String)*
	* **time**: *(Date)*
	* **offset**: *(Number)* timezone offset in seconds from GMT.
	###

	constructor: (obj) ->
		_immutable(@, obj)
			.set("name")
			.set("email")
			.set("time")
			.set("offset")


Gitteh.Refspec = class Refspec
	###
	Describes the way remote repository references will be mapped to the local
	repository. 

	For more information refer to http://git-scm.com/book/ch9-5.html
	###

	constructor: (src, dst) ->
		_priv = _createPrivate @

		_priv.srcRoot = if src? and src[-1..] is "*" then src[0...-1] else src
		_priv.dstRoot = if dst? and dst[-1..] is "*" then dst[0...-1] else dst

		_immutable(@, {src, dst})
			.set("src")
			.set("dst")

	matchesSrc: (refName) ->
		###
		Returns true/false if given `refName` matches source of this Refspec.
		###
		_priv = _getPrivate @
		return false if refName.length <= _priv.srcRoot.length
		return refName.indexOf(_priv.srcRoot) is 0

	matchesDst: (refName) ->
		###
		Returns true/false if given `refName` matches destination of this
		Refspec.
		###
		_priv = _getPrivate @
		return false if refName.length <= _priv.dstRoot.length
		return refName.indexOf(_priv.dstRoot) is 0

	transformTo: (refName) ->
		###
		Transforms given `refName` to destination, provided it matches src
		pattern, and throws an error if it doesn't.
		###
		throw new Error "Ref doesn't match src." if not @matchesSrc refName
		return "#{@dst[0...-2]}#{refName[(@src.length-2)..]}"

	transformFrom: (refName) ->
		###
		Transforms provided refName from destination back to source, provided it
		matches dst pattern, and throws an Error if it doesn't. This is the
		reverse of :func:`gitteh::Refspec.transformTo`
		###
		throw new Error "Ref doesn't match dst." if not @matchesDst refName
		return "#{@src[0...-2]}#{refName[(@dst.length-2)..]}"


Gitteh.Commit = class Commit
	###
	Commits, made by an author, and an optional different committer, contain a
	message, an associated :class:`gitteh::Tree`, and zero or more parent
	:class:`gitteh::Commit` objects. Zero parents generally indicate the initial 
	commit for the repository. More than one parent commits indicate a merge
	commit.

	Properties:

	* **id**: *(String)* OID of this commit (SHA1 hash)
	* **treeId**: *(String)* OID of associated :class:`gitteh::Tree`
	* **parents**: *(String[]) list of parent commit OIDs
	* **message**: *(String)*
	* **messageEncoding**: *(???)* ??? TODO:
	* **author**: (:class:`gitteh::Signature`)
	* **committer**: (:class:`gitteh::Signature`)
	###

	constructor: (@repository, obj) ->
		obj.author = new Signature obj.author
		obj.committer = new Signature obj.committer
		_immutable(@, obj)
			.set("id")
			.set("tree", "treeId")
			.set("parents")
			.set("message")
			.set("messageEncoding")
			.set("author")
			.set("committer")

	tree: (cb) ->
		###
		Fetches the :class:`gitteh::Tree` for this Commit. Shortcut for calling
		:func:`gitteh::Repository.tree` with this commits `treeId`.
		###
		@repository.tree @treeId, cb	


Gitteh.Tree = class Tree
	###
	A Tree contains a list of named entries, which can either be
	:class:`gitteh::Blob` objects or nested :class:`gitteh::Tree` objects. Each
	entry is referenced by its OID.

	Properties:

	* **id**: *(String)* OID of this Tree.
	* **entries**: *(TreeEntry[])* 

	## Tree Entries
	
	Each element of a Tree contains the following properties:

	* **id**: *(String)* OID this entry points to.
	* **name**: *(String)* file name of this entry.
	* **type**: *(String)* kind of object pointed to by this entry
	* **attributes**: *(Number)* UNIX file attributes for this entry.
	###

	constructor: (@repository, obj) ->
		obj._entries = obj.entries
		obj.entries = []
		for origEntry in obj._entries
			obj.entries.push entry = {}
			_immutable(entry, origEntry)
				.set("id")
				.set("name")
				.set("type")
				.set("attributes")
		_immutable(@, obj)
			.set("id")
			.set("entries")


Gitteh.Blob = class Blob
	###
	Contains raw data for a file stored in Git.

	Properties:

	* **id**: *(String)* OID of this Blob.
	* **data**: *(Buffer)* a standard Node buffer containing binary data.
	###

	constructor: (@repository, obj) ->
		_immutable(@, obj)
			.set("id")
			.set("data")


Gitteh.Tag = class Tag
	###*
	 * @class
	 * Git tags are similar to references, and indeed "lightweight" Git tags are 
	 * actually implemented as References with a name prefix of "tags/". When 
	 * additional metadata is needed (message/name/email/GPG signature), a proper
	 * heavyweight Tag object is used.
	 * @property {String} id object id of this Tag.
	 * @property {String} name
	 * @property {String} message
	 * @property {Signature} tagger
	 * @property {String} targetId object id this Tag points to
	 * @property {String} type the type of object this Tag points to.
	###
	constructor: (@repository, obj) ->
		obj.tagger = new Signature obj.tagger
		_immutable(@, obj)
			.set("id")
			.set("name")
			.set("message")
			.set("tagger")
			.set("target", "targetId")
			.set("type")
	target: (cb) ->
		###*
		 * Convenience method to get the object this Tag points to. Shorthand for 
		 * {@link Repository#object}(tag.targetId)
		 * @param {Function} cb called when target object has been loaded.
		 * @see Repository#object
		###
		@repository.object @targetId, @type, cb

Gitteh.Remote = class Remote
	###*
	 * @class
	 * Remotes designate the location and rules of remote Git repositories. Remotes
	 * can be obtained by using {@link Repository.remote}.
	 * @property {Boolean} connected true if there is an active connection to the
	 * Remotes' endpoint.
	 * @property {String} name
	 * @property {String} url address of Remotes' endpoint
	 * @property {Refspec} fetchSpec Refspec used when fetching from Remote
	 * @property {Refspec} pushSpec Refspec used when pushing to Remote
	 * @property {String} HEAD the remote HEAD reference name (only set after 
	 * connected to Remote)
	 * @property {String[]} refs names of references on remote (only set after 
	 * connected to Remote)
	 * @see Repository.remote
	###
	constructor: (@repository, nativeRemote) ->
		_priv = _createPrivate @
		_priv.native = nativeRemote
		_priv.connected = false

		if nativeRemote not instanceof NativeRemote
			throw new Error "Don't construct me, see Repository.remote()"

		Object.defineProperty @, "connected",
			get: -> return _priv.connected
			enumerable: true
			configurable: false

		_immutable(@, nativeRemote)
			.set("name")
			.set("url")

		fetchSpec = new Refspec nativeRemote.fetchSpec.src, nativeRemote.fetchSpec.dst
		pushSpec = new Refspec nativeRemote.pushSpec.src, nativeRemote.pushSpec.dst
		_immutable(@, {fetchSpec, pushSpec})
			.set("fetchSpec")
			.set("pushSpec")

	connect: ->
		###*
		 * Opens a connection to the Remote endpoint. This is needed before 
		 * {@link #fetch} or {@link #push} can be called.
		 * @param {String} direction The direction of the connection, must be either
		 * "push" or "fetch".
		 * @param {Function} cb called when connection has been made, or fails.
		###
		_priv = _getPrivate @
		[dir, cb] = args
			dir: type: "remoteDir"
			cb: type: "function"
		dir = if dir is "push" then bindings.GIT_DIRECTION_PUSH else bindings.GIT_DIRECTION_FETCH
		_priv.native.connect dir, _wrapCallback cb, (refs) =>
			refNames = Object.keys refs

			# Determine symref for HEAD.
			headOid = refs["HEAD"]
			for ref, oid of refs
				continue if ref is "HEAD"
				if oid is headOid
					headRef = @fetchSpec.transformTo ref
					_immutable(@, {headRef}).set "headRef", "HEAD"
					break

			_immutable(@, {refNames}).set "refNames", "refs"
			_priv.connected = true
			cb()

	fetch: ->
		###*
		 * Fetches Git objects from remote that do not exist locally.
		 * @param {Function} progressCb called to notify of progress with fetch process.
		 * @param {Function} cb called when fetch has been completed.
		###
		_priv = _getPrivate @
		throw new Error "Remote isn't connected." if not @connected
		[progressCb, cb] = args
			progressCb: type: "function"
			cb: type: "function"

		updateTimer = null
		update = =>
			{bytes, total, done} = _priv.native.stats
			progressCb bytes, total, done
			updateTimer = setTimeout update, 500
		setTimeout update, 500

		_priv.native.download (err) =>
			clearTimeout updateTimer
			return cb err if err?
			_priv.native.updateTips _wrapCallback cb, =>
				cb()

Gitteh.Index = class Index
	constructor: (nativeIndex) ->
		###
		 * @class
		 * The Git index is used to stage changed files before they are written to the 
		 * repository proper. Bindings for the Index are currently minimal.
		###
		_priv = _createPrivate @
		_priv.native = nativeIndex

	readTree: ->
		###
		 * Updates the Git index to reflect the state of provided {@link Tree}.
		 * @param {String} id object id of Tree to be read.
		 * @param {Function} cb called when index update has been completed.
		###
		_priv = _getPrivate @
		[id, cb] = args
			id: type: "oid"
			cb: type: "function"
		_priv.native.readTree id, cb

	write = ->
		###
		 * Synchronizes the in-memory Git index with the indexfile located in repository
		 * @param {Function} cb called when synchronization is complete.
		###
		_priv = _getPrivate @
		[cb] = args
			cb: type: "function"
		_priv.native.write cb


Gitteh.Reference = class Reference
	###*
	 * @class
	 * A Reference is a named pointer to a {@link Commit} object. That is, refs are
	 * the DNS of Git-land. References can either be direct or symbolic. Direct 
	 * references point to the object id of a commit. Symbolic refs point to other
	 * references.
	 * @property {String} name
	 * @property {Boolean} direct true if Reference points directly to an object id.
	 * @property {Boolean} packed true if Reference is in a packfile
	 * @property {String} target object id reference points to, or another reference
	 * name if not a direct reference.
	 * @property {Repository} repository the {@link Repository} that owns this ref.
	 * @see Repository#reference
	 * @see Repository#createReference
	###

	constructor: (repo, nativeRef) ->
		_priv = _createPrivate @
		_priv.native = nativeRef
		_immutable(@, nativeRef)
			.set("name")
			.set("direct")
			.set("packed")
			.set("target")
		_immutable(@, {repo}).set "repo", "repository"


Gitteh.Repository = class Repository
	###*
	 * @class
	 * Represents a local Git repository that has been opened by Gitteh. Used to get
	 * access to any objects contained within it.
	 * 
	 * Repositories can be bare - they will not have a working directory, in this
	 * case the contents of what is usually in a .git subdirectory will be in the
	 * top level.
	 * @property {Boolean} bare true if this repository is bare.
	 * @property {String} path location of the Git metadata directory
	 * @property {String} workingDirectory location of the working directory, if 
	 * applicable (non-bare repository)
	 * @property {String[]} remotes  names of remotes configured for this repository
	 * @property {String[]} references names of references contained in this 
	 * repository.
	 * @property {Index} index The Git index for this repository.
	###

	constructor: (nativeRepo) ->
		if nativeRepo not instanceof NativeRepository
			throw new Error "Don't construct me, see gitteh.(open|init)Repository"
		_priv = _createPrivate @
		_priv.native = nativeRepo

		_immutable(@, nativeRepo)
			.set("bare")
			.set("path")
			.set("workDir", "workingDirectory")
			.set("remotes")
			.set("references")
			.set("submodules")
		index = new Index nativeRepo.index
		_immutable(@, {index}).set "index"
	exists: ->
		###*
		 * Checks if an object with given objectid exists.
		 * @param {String} oid ID of object in question.
		 * @param {Function} cb Called with status of object existence.
		###
		_priv = _getPrivate @
		[oid, cb] = args
			oid: type: "oid"
			cb: type: "function"
		_priv.native.exists oid, cb

	object: ->
		###
		 * Fetches an object with given ID. The object returned will be a Gitteh wrapper
		 * corresponding to the type of Git object fetched. Alternatively, objects with
		 * an expected type can be fetched using the {@link #blob}, {@link #commit},
		 * {@link #tag}, {@link #tree}, {@link #reference} methods.
		 * @param {String} oid id of object to be fetched.
		 * @param {Function} cb called when object has been fetched.
		 * @see Commit
		 * @see Blob
		 * @see Tag
		 * @see Tree
		 * @see Reference
		###
		_priv = _getPrivate @
		[oid, type, cb] = args
			oid: type: "oid"
			type: type: "objectType", default: "any"
			cb: type: "function"
		_priv.native.object oid, type, _wrapCallback cb, (object) =>
			clazz = switch object._type
				when types.commit then Commit
				when types.tree then Tree
				when types.blob then Blob
				when types.tag then Tag
				else undefined
			return cb new TypeError("Unexpected object type") if clazz is undefined
			return cb null, new clazz @, object

	blob: (oid, cb) ->
		###
		 * Fetches a {@link Blob} object from the repository. This is a stricter
		 * variant of {@link #object} - an error will be thrown if object isnt a blob.
		 * @param {String} oid id of blob to be fetched.
		 * @param {Function} cb called when blob has been fetched.
		 * @see #object
		###
		@object oid, "blob", cb

	commit: (oid, cb) ->
		###*
		 * Fetches a {@link Commit} object from the repository. This is a stricter
		 * variant of {@link #object} - an error will be thrown if object isnt a commit.
		 * @param {String} oid id of commit to be fetched.
		 * @param {Function} cb called when commit has been fetched.
		 * @see #object
		###
		@object oid, "commit", cb

	tag: (oid, cb) ->
		###*
		 * Fetches a {@link Tag} object from the repository. This is a stricter
		 * variant of {@link #object} - an error will be thrown if object isnt a tag.
		 * @param {String} oid id of tag to be fetched.
		 * @param {Function} cb called when tag has been fetched.
		 * @see #object
		###
		@object oid, "tag", cb

	tree: (oid, cb) ->
		###*
		 * Fetches a {@link Tree} object from the repository. This is a stricter
		 * variant of {@link #object} - an error will be thrown if object isnt a tree.
		 * @param {String} oid id of tree to be fetched.
		 * @param {Function} cb called when tree has been fetched.
		 * @see #object
		###
		@object oid, "tree", cb

	reference: ->
		###*
		 * Fetches a {@link Reference} object from the repository. This is a stricter 
		 * variant of {@link #object} - an error will be thrown if object isnt a ref.
		 * @param {String} oid id of reference to be fetched.
		 * @param {Function} cb called when reference has been fetched.
		 * @see #object
		###
		_priv = _getPrivate @
		[name, resolve, cb] = args
			name: type: "string"
			resolve: type: "bool", default: false
			cb: type: "function"
		_priv.native.reference name, resolve, _wrapCallback cb, (ref) =>
			cb null, new Reference @, ref

	createReference: ->
		###*
		 * Creates a new reference, which can either by direct or symbolic.
		 * @param {String} name
		 * @param {String} target reference/oid targetted by the new reference.
		 * @param {Boolean} [force=false] force creation of this reference, destroying 
		 * the reference with same name, if it exists.
		 * @param {Function} cb called when reference has been created.
		 * @see Reference
		###
		_priv = _getPrivate @
		[name, target, force, cb] = args
			name: type: "string"
			target: type: "string"
			force: type: "bool", default: false
			cb: type: "function"
		fn = "createSymReference"
		if target.length is 40 and args.oidRegex.test target
			fn = "createOidReference"
		_priv.native[fn] name, target, force, _wrapCallback cb, (ref) =>
			cb null, new Reference @, ref

	remote: ->
		###*
		 * Loads a remote with given name.
		 * @param {String} name
		 * @param {Function} cb called when remote has been loaded.
		###
		_priv = _getPrivate @
		[name, cb] = args
			name: type: "string"
			cb: type: "function"
		_priv.native.remote name, _wrapCallback cb, (remote) =>
			return cb null, new Remote @, remote

	createRemote: ->
		###*
		 * Create a new {@link Remote} for this repository.
		 * @param {String} name
		 * @param {String} url 
		 * @param {Function} cb called when Remote has been created.
		 * @see Remote
		###
		_priv = _getPrivate @
		[name, url, cb] = args
			name: type: "string"
			url: type: "string"
			cb: type: "function"
		_priv.native.createRemote name, url, _wrapCallback cb, (remote) =>
			return cb null, new Remote @, remote

###*
 * Alias of {@link #reference}.
 * @param {String} oid id of reference to be fetched.
 * @param {Function} cb called when reference has been fetched.
 * @see #reference
###
Repository.prototype.ref = Repository.prototype.reference


Gitteh.openRepository = ->
	###*
	 * Opens a local Git repository.
	 * @param {String} path The path to the local git repo.
	 * @param {Function} cb Called when {@link Repository} has opened.
	 * @see Repository
	###
	[path, cb] = args
		path: type: "string"
		cb: type: "function"
	bindings.openRepository path, _wrapCallback cb, (repo) ->
		cb null, new Repository repo

Gitteh.initRepository = () ->
	###*
	 * @param {String} path Path where new Git repository should be created.
	 * @param {Boolean} [bare=false] When true creates a bare repo. Bare repositories 
	 have no working directory.
	 * @param {Function} cb Called when {@link Repository} has been created.
	 * Creates a new local Git repository.
	###
	[path, bare, cb] = args
		path: type: "string"
		bare: type: "bool", default: false
		cb: type: "function"
	bindings.initRepository path, bare, _wrapCallback cb, (repo) ->
		cb null, new Repository repo

Gitteh.clone = =>
	###*
	 * Clones a remote Git repository to the local machine. Currently, only HTTP/Git
	 * protocols are supported (no git+ssh yet).
	 * @param {String} url Address of remote Git repository.
	 * @param {String} path Destination path for cloned repository.
	###
	[url, path, cb] = args
		url: type: "string"
		path: type: "string"

	emitter = new EventEmitter

	async.waterfall [
		# Initialize a fresh repo in the path specified.
		(cb) -> Gitteh.initRepository path, false, cb

		# Create the origin remote with provided URL.
		(repo, cb) ->
			repo.createRemote "origin", url, _wrapCallback cb, (remote) ->
				cb null, repo, remote

		# Connect to the remote to commence fetch.
		(repo, remote, cb) ->
			remote.connect "fetch", _wrapCallback cb, ->
				cb null, repo, remote

		# Perform the actual fetch, sending progress updates as they come in.
		(repo, remote, cb) ->
			emitProgress = (bytes, done, complete) ->
				emitter.emit "status", bytes, done, complete
			remote.fetch emitProgress, _wrapCallback cb, ->
				cb null, repo, remote

		# The connect step earlier resolved remote HEAD. Let's fetch that ref.
		(repo, remote, cb) ->
			repo.ref remote.HEAD, true, _wrapCallback cb, (ref) ->
				cb null, repo, remote, ref

		# We now have fully resolved OID head ref. Create a local branch.
		(repo, remote, headRef, cb) ->
			refName = remote.fetchSpec.transformFrom remote.HEAD
			repo.createReference refName, headRef.target, _wrapCallback cb, ->
				cb null, repo, remote, headRef

		# And now fetch the commit.
		(repo, remote, headRef, cb) ->
			repo.commit headRef.target, _wrapCallback cb, (commit) ->
				cb null, repo, remote, commit

		# Now fetch the tree for the commit.
		(repo, remote, headCommit, cb) ->
			headCommit.tree _wrapCallback cb, (tree) ->
				cb null, repo, remote, tree

		# Now we can go ahead and checkout this tree into working directory.
		(repo, remote, headTree, cb) ->
			handleEntry = (dest, entry, cb) ->
				if entry.type is "tree"
					subPath = _path.join dest, entry.name
					async.series [
						# TODO: mode?
						(cb) -> fs.mkdir subPath, cb
						(cb) ->
							repo.tree entry.id, _wrapCallback cb, (subtree) ->
								checkoutTree subtree, subPath, cb
					], cb
				else if entry.type is "blob"
					repo.blob entry.id, _wrapCallback cb, (blob) ->
						file = fs.createWriteStream _path.join(dest, entry.name), 
							mode: entry.attributes
						file.write blob.data
						file.end()
						cb()
				else
					cb()
			checkoutTree = (tree, dest, cb) ->
				async.forEach tree.entries, handleEntry.bind(null, dest), cb
			checkoutTree headTree, repo.workingDirectory, _wrapCallback cb, ->
				cb null, repo, remote, headTree

		# Update the git index with the tree we just checked out.
		(repo, remote, headTree, cb) ->
			repo.index.readTree headTree.id, _wrapCallback cb, ->
				cb null, repo, remote

		# Now write the index back to disk.
		(repo, remote, cb) ->
			repo.index.write _wrapCallback cb, ->
				cb null, repo, remote
	], (err, repo) ->
		return emitter.emit "error", err if err?

		emitter.emit "complete", repo

	return emitter
