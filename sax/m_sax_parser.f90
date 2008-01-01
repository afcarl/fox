module m_sax_parser

  use m_common_array_str, only: str_vs, string_list, &
    destroy_string_list, vs_str_alloc, vs_vs_alloc
  use m_common_attrs, only: init_dict, destroy_dict, reset_dict, &
    add_item_to_dict, has_key, get_value
  use m_common_charset, only: XML_WHITESPACE
  use m_common_element, only: element_t, existing_element, add_element, &
    get_element, parse_dtd_element, parse_dtd_attlist, report_declarations, &
    get_att_type, get_default_atts, declared_element, ATT_CDATA
  use m_common_elstack, only: push_elstack, pop_elstack, init_elstack, &
    destroy_elstack, is_empty, len, get_top_elstack
  use m_common_entities, only: existing_entity, init_entity_list, &
    destroy_entity_list, add_internal_entity, &
    expand_entity, expand_char_entity, pop_entity_list, size, &
    entity_t, getEntityByIndex, getEntityByName
  use m_common_entity_expand, only: expand_entity_value_alloc
  use m_common_error, only: FoX_error, add_error, &
    init_error_stack, destroy_error_stack, in_error
  use m_common_namecheck, only: checkName, checkPublicId, &
    checkCharacterEntityReference, likeCharacterEntityReference, &
    checkQName, checkNCName, checkPITarget, &
    checkRepCharEntityReference
  use m_common_namespaces, only: getnamespaceURI, invalidNS, &
    checkNamespaces, checkEndNamespaces, namespaceDictionary, &
    initNamespaceDictionary, destroyNamespaceDictionary
  use m_common_notations, only: init_notation_list, destroy_notation_list, &
    add_notation, notation_exists
  use m_common_struct, only: init_xml_doc_state, &
    destroy_xml_doc_state, register_internal_PE, register_external_PE, &
    register_internal_GE, register_external_GE

  use FoX_utils, only: URI, parseURI, rebaseURI, expressURI, destroyURI, &
    hasFragment

  use m_sax_reader, only: file_buffer_t, pop_buffer_stack, open_new_string, &
    open_new_file, parse_xml_declaration, parse_text_declaration, &
    reading_main_file
  use m_sax_tokenizer, only: sax_tokenize, normalize_text
  use m_sax_types ! everything, really

  implicit none
  private

  public :: getNSDict

  public :: sax_parser_init
  public :: sax_parser_destroy
  public :: sax_parse

contains

  function getNSDict(fx) result(ns)
    type(sax_parser_t), target :: fx
    type(namespaceDictionary), pointer :: ns

    ns => fx%nsDict
  end function getNSDict

  subroutine sax_parser_init(fx, fb)
    type(sax_parser_t), intent(out) :: fx
    type(file_buffer_t), intent(in) :: fb

    allocate(fx%token(0))

    call init_error_stack(fx%error_stack)
    call init_elstack(fx%elstack)
    call init_dict(fx%attributes)

    call initNamespaceDictionary(fx%nsdict)
    call init_notation_list(fx%nlist)
    allocate(fx%xds)
    call init_xml_doc_state(fx%xds)
    deallocate(fx%xds%inputEncoding)
    fx%xds%inputEncoding => vs_str_alloc("us-ascii")
    ! because it always is ...
    if (fb%f(1)%lun>0) then
      fx%xds%documentURI => vs_vs_alloc(fb%f(1)%filename)
    else
      fx%xds%documentURI => vs_str_alloc("")
    endif

    fx%xds%standalone = fb%standalone

    allocate(fx%wf_stack(1))
    fx%wf_stack(1) = 0
    call init_entity_list(fx%forbidden_ge_list)
    call init_entity_list(fx%forbidden_pe_list)
    call init_entity_list(fx%predefined_e_list)

    call add_internal_entity(fx%predefined_e_list, 'amp', '&')
    call add_internal_entity(fx%predefined_e_list, 'lt', '<')
    call add_internal_entity(fx%predefined_e_list, 'gt', '>')
    call add_internal_entity(fx%predefined_e_list, 'apos', "'")
    call add_internal_entity(fx%predefined_e_list, 'quot', '"')
  end subroutine sax_parser_init

  subroutine sax_parser_destroy(fx)
    type(sax_parser_t), intent(inout) :: fx

    fx%context = CTXT_NULL
    fx%state = ST_NULL

    if (associated(fx%token)) deallocate(fx%token)
    if (associated(fx%root_element)) deallocate(fx%root_element)

    call destroy_error_stack(fx%error_stack)
    call destroy_elstack(fx%elstack)
    call destroy_dict(fx%attributes)
    call destroyNamespaceDictionary(fx%nsdict)
    call destroy_notation_list(fx%nlist)
    if (.not.fx%xds_used) then
      call destroy_xml_doc_state(fx%xds)
      deallocate(fx%xds)
    endif

    deallocate(fx%wf_stack)
    call destroy_entity_list(fx%forbidden_ge_list)
    call destroy_entity_list(fx%forbidden_pe_list)
    call destroy_entity_list(fx%predefined_e_list)

    if (associated(fx%token)) deallocate(fx%token)
    if (associated(fx%name)) deallocate(fx%name)
    if (associated(fx%attname)) deallocate(fx%attname)
    if (associated(fx%publicId)) deallocate(fx%publicId)
    if (associated(fx%systemId)) deallocate(fx%systemId)
    if (associated(fx%Ndata)) deallocate(fx%Ndata)

  end subroutine sax_parser_destroy

  recursive subroutine sax_parse(fx, fb, &
                                ! org.xml.sax
                                ! SAX ContentHandler
    characters_handler,            &
    endDocument_handler,           &
    endElement_handler,            &
    endPrefixMapping_handler,      &
    ignorableWhitespace_handler,   &
    processingInstruction_handler, &
                                ! setDocumentLocator
    skippedEntity_handler,         &
    startDocument_handler,         & 
    startElement_handler,          &
    startPrefixMapping_handler,    &
                                ! SAX DTDHandler
    notationDecl_handler,          &
    unparsedEntityDecl_handler,    &
                                ! SAX ErrorHandler
    error_handler,                 &
    fatalError_handler,            &
    warning_handler,               &
                                ! org.xml.sax.ext
                                ! SAX DeclHandler
    attributeDecl_handler,         &
    elementDecl_handler,           &
    externalEntityDecl_handler,    &
    internalEntityDecl_handler,    &
                                ! SAX LexicalHandler
    comment_handler,               &
    endCdata_handler,              &
    endDTD_handler,                &
    endEntity_handler,             &
    startCdata_handler,            &
    startDTD_handler,              &
    startEntity_handler,           &
    namespaces,                    &
    namespace_prefixes,            &
    xmlns_uris,                    &
    validate,                      &
    FoX_endDTD_handler,            &
    startInCharData,               &
    initial_entities)

    type(sax_parser_t), intent(inout) :: fx
    type(file_buffer_t), intent(inout) :: fb
    optional :: characters_handler
    optional :: endDocument_handler
    optional :: endElement_handler
    optional :: endPrefixMapping_handler
    optional :: ignorableWhitespace_handler
    optional :: processingInstruction_handler
    optional :: skippedEntity_handler
    optional :: startElement_handler
    optional :: startDocument_handler
    optional :: startPrefixMapping_handler
    optional :: notationDecl_handler
    optional :: unparsedEntityDecl_handler
    optional :: error_handler
    optional :: fatalError_handler
    optional :: warning_handler
    optional :: attributeDecl_handler
    optional :: elementDecl_handler
    optional :: externalEntityDecl_handler
    optional :: internalEntityDecl_handler
    optional :: comment_handler
    optional :: endCdata_handler
    optional :: endEntity_handler
    optional :: endDTD_handler
    optional :: FoX_endDTD_handler
    optional :: startCdata_handler
    optional :: startDTD_handler
    optional :: startEntity_handler

    logical, intent(in), optional :: namespaces
    logical, intent(in), optional :: namespace_prefixes
    logical, intent(in), optional :: xmlns_uris

    logical, intent(in), optional :: validate
    logical, intent(in), optional :: startInCharData

    type(entity_list), optional :: initial_entities

    interface

      subroutine characters_handler(chunk)
        character(len=*), intent(in) :: chunk
      end subroutine characters_handler

      subroutine endDocument_handler()     
      end subroutine endDocument_handler

      subroutine endElement_handler(namespaceURI, localName, name)
        character(len=*), intent(in)     :: namespaceURI
        character(len=*), intent(in)     :: localName
        character(len=*), intent(in)     :: name
      end subroutine endElement_handler

      subroutine endPrefixMapping_handler(prefix)
        character(len=*), intent(in) :: prefix
      end subroutine endPrefixMapping_handler

      subroutine ignorableWhitespace_handler(chars)
        character(len=*), intent(in) :: chars
      end subroutine ignorableWhitespace_handler

      subroutine processingInstruction_handler(name, content)
        character(len=*), intent(in)     :: name
        character(len=*), intent(in)     :: content
      end subroutine processingInstruction_handler

      subroutine skippedEntity_handler(name)
        character(len=*), intent(in) :: name
      end subroutine skippedEntity_handler

      subroutine startDocument_handler()   
      end subroutine startDocument_handler

      subroutine startElement_handler(namespaceURI, localName, name, attributes)
        use FoX_common
        character(len=*), intent(in)     :: namespaceUri
        character(len=*), intent(in)     :: localName
        character(len=*), intent(in)     :: name
        type(dictionary_t), intent(in)   :: attributes
      end subroutine startElement_handler

      subroutine startPrefixMapping_handler(namespaceURI, prefix)
        character(len=*), intent(in) :: namespaceURI
        character(len=*), intent(in) :: prefix
      end subroutine startPrefixMapping_handler

      subroutine notationDecl_handler(name, publicId, systemId)
        character(len=*), intent(in) :: name
        character(len=*), intent(in) :: publicId
        character(len=*), intent(in) :: systemId
      end subroutine notationDecl_handler

      subroutine unparsedEntityDecl_handler(name, publicId, systemId, notation)
        character(len=*), intent(in) :: name
        character(len=*), intent(in) :: publicId
        character(len=*), intent(in) :: systemId
        character(len=*), intent(in) :: notation
      end subroutine unparsedEntityDecl_handler

      subroutine error_handler(msg)
        character(len=*), intent(in)     :: msg
      end subroutine error_handler

      subroutine fatalError_handler(msg)
        character(len=*), intent(in)     :: msg
      end subroutine fatalError_handler

      subroutine warning_handler(msg)
        character(len=*), intent(in)     :: msg
      end subroutine warning_handler

      subroutine attributeDecl_handler(eName, aName, type, mode, value)
        character(len=*), intent(in) :: eName
        character(len=*), intent(in) :: aName
        character(len=*), intent(in) :: type
        character(len=*), intent(in), optional :: mode
        character(len=*), intent(in), optional :: value
      end subroutine attributeDecl_handler

      subroutine elementDecl_handler(name, model)
        character(len=*), intent(in) :: name
        character(len=*), intent(in) :: model
      end subroutine elementDecl_handler

      subroutine externalEntityDecl_handler(name, publicId, systemId)
        character(len=*), intent(in) :: name
        character(len=*), optional, intent(in) :: publicId
        character(len=*), intent(in) :: systemId
      end subroutine externalEntityDecl_handler

      subroutine internalEntityDecl_handler(name, value)
        character(len=*), intent(in) :: name
        character(len=*), intent(in) :: value
      end subroutine internalEntityDecl_handler

      subroutine comment_handler(comment)
        character(len=*), intent(in) :: comment
      end subroutine comment_handler

      subroutine endCdata_handler()
      end subroutine endCdata_handler

      subroutine endDTD_handler()
      end subroutine endDTD_handler

      subroutine FoX_endDTD_handler(state)
        use m_common_struct, only: xml_doc_state
        type(xml_doc_state), pointer :: state
      end subroutine FoX_endDTD_handler

      subroutine endEntity_handler(name)
        character(len=*), intent(in) :: name
      end subroutine endEntity_handler

      subroutine startCdata_handler()
      end subroutine startCdata_handler

      subroutine startDTD_handler(name, publicId, systemId)
        character(len=*), intent(in) :: name
        character(len=*), intent(in) :: publicId
        character(len=*), intent(in) :: systemId
      end subroutine startDTD_handler

      subroutine startEntity_handler(name)
        character(len=*), intent(in) :: name
      end subroutine startEntity_handler

    end interface

    logical :: validCheck, startInCharData_, processDTD, pe, nameOK, eof
    logical :: namespaces_, namespace_prefixes_, xmlns_uris_
    integer :: i, iostat, temp_i, nextState
    character, pointer :: tempString(:)
    character :: dummy
    type(element_t), pointer :: elem
    type(entity_t), pointer :: ent
    type(URI), pointer :: URIref, newURI
    integer, pointer :: temp_wf_stack(:)
    integer :: section_depth

    nullify(tempString)
    nullify(elem)

    if (present(namespaces)) then
      namespaces_ = namespaces
    else
      namespaces_ = .true.
    endif
    if (present(namespace_prefixes)) then
      namespace_prefixes_ = namespace_prefixes
    else
      namespace_prefixes_ = .false.
    endif
    if (present(xmlns_uris)) then
      xmlns_uris_ = xmlns_uris
    else
      xmlns_uris_ = .false.
    endif
    if (present(validate)) then
      validCheck = validate
    else
      validCheck = .false.
    endif
    if (present(startInCharData)) then
      startInCharData_ = startInCharData
    else
      startInCharData_ = .false.
    endif
    if (present(initial_entities)) then
      do i = 1, size(initial_entities)
        ent => getEntityByIndex(initial_entities, i)
        if (.not.ent%external) &
          call register_internal_PE(fx%xds, &
          name=str_vs(ent%name), text=str_vs(ent%text))
      enddo
    endif

    section_depth = 0
    processDTD = .true.
    iostat = 0

    if (startInCharData_) then
      fx%context = CTXT_IN_CONTENT
      fx%state = ST_CHAR_IN_CONTENT
      fx%well_formed = .true.
    elseif (reading_main_file(fb)) then
      fx%context = CTXT_BEFORE_DTD
      fx%state = ST_MISC
      if (present(startDocument_handler)) then
        call startDocument_handler()
        if (fx%state==ST_STOP) goto 100
      endif
      call parse_xml_declaration(fb, fx%xds%xml_version, fx%xds%encoding, fx%xds%standalone, fx%error_stack)
      if (in_error(fx%error_stack)) goto 100
    endif

    do

      call sax_tokenize(fx, fb, eof)
      if (in_error(fx%error_stack)) then
        ! Any error, we want to quit sax_tokenizer
        call add_error(fx%error_stack, 'Error getting token')
        goto 100
      elseif (eof.and..not.reading_main_file(fb)) then
        if (fx%context==CTXT_IN_DTD) then
          ! that's just the end of a parameter entity expansion.
          ! pop the parse stack, and carry on ..
          if (present(endEntity_handler)) then
            call endEntity_handler('%'//pop_entity_list(fx%forbidden_pe_list))
            if (fx%state==ST_STOP) goto 100
          else
            dummy = pop_entity_list(fx%forbidden_pe_list)
          endif
        elseif (fx%context==CTXT_IN_CONTENT) then
          if (fx%state==ST_TAG_IN_CONTENT) fx%state = ST_CHAR_IN_CONTENT
          ! because CHAR_IN_CONTENT *always* leads to TAG_IN_CONTENT
          ! *except* when it is the end of an entity expansion
          ! it's the end of a general entity expansion
          if (present(endEntity_handler)) then
            call endEntity_handler(pop_entity_list(fx%forbidden_ge_list))
            if (fx%state==ST_STOP) goto 100
          else
            dummy = pop_entity_list(fx%forbidden_ge_list)
          endif
          if (fx%state/=ST_CHAR_IN_CONTENT.or.fx%wf_stack(1)/=0) then
            call add_error(fx%error_stack, 'Ill-formed entity')
            goto 100
          endif
          temp_wf_stack => fx%wf_stack
          allocate(fx%wf_stack(size(temp_wf_stack)-1))
          fx%wf_stack = temp_wf_stack(2:size(temp_wf_stack))
          deallocate(temp_wf_stack)
        endif
        call pop_buffer_stack(fb)
        cycle
      endif
      if (fx%tokenType==TOK_NULL) then
        call add_error(fx%error_stack, 'Internal error! No token found!')
        goto 100
      endif
      print*, "=============="
      print*, fx%state, fx%tokenType, fx%nextTokenType
      if (associated(fx%token)) print*, str_vs(fx%token)

      nextState = ST_NULL

      select case (fx%state)

      case (ST_MISC)
        write(*,*) 'ST_MISC', str_vs(fx%token)
        select case (fx%tokenType)
        case (TOK_PI_TAG)
          nextState = ST_START_PI
        case (TOK_BANG_TAG)
          nextState = ST_BANG_TAG
        case (TOK_OPEN_TAG)
          nextState = ST_START_TAG
        end select

      case (ST_BANG_TAG)
        write(*,*) 'ST_BANG_TAG'
        select case (fx%tokenType)
        case (TOK_OPEN_SB)
          nextState = ST_START_SECTION_DECLARATION
        case (TOK_OPEN_COMMENT)
          nextState = ST_START_COMMENT
        case (TOK_NAME)
          if (fx%context==CTXT_BEFORE_DTD) then
            if (str_vs(fx%token)=='DOCTYPE') then
              fx%context = CTXT_IN_DTD
              nextState = ST_IN_DTD
            endif
          elseif (fx%context==CTXT_IN_DTD) then
            if (str_vs(fx%token)=='ATTLIST') then
              nextState = ST_DTD_ATTLIST
            elseif (str_vs(fx%token)=='ELEMENT') then
              nextState = ST_DTD_ELEMENT
            elseif (str_vs(fx%token)=='ENTITY') then
              nextState = ST_DTD_ENTITY
            elseif (str_vs(fx%token)=='NOTATION') then
              nextState = ST_DTD_NOTATION
            endif
          endif
        end select


      case (ST_START_PI)
        write(*,*)'ST_START_PI'
        select case (fx%tokenType)
        case (TOK_NAME)
          if (namespaces_) then
            nameOk = checkNCName(str_vs(fx%token), fx%xds)
          else
            nameOk = checkName(str_vs(fx%token), fx%xds)
          endif
          if (nameOk) then
            if (str_vs(fx%token)=='xml') then
              call add_error(fx%error_stack, "XML declaration must be at start of document")
              goto 100
            elseif (checkPITarget(str_vs(fx%token), fx%xds)) then
              nextState = ST_PI_CONTENTS
              fx%name => fx%token
              fx%token => null()
            else
              call add_error(fx%error_stack, "Invalid PI target name")
              goto 100
            endif
          endif
        end select

      case (ST_PI_CONTENTS)
        write(*,*)'ST_PI_CONTENTS'
        if (validCheck.and.len(fx%elstack)>0) then
          elem => get_element(fx%xds%element_list, get_top_elstack(fx%elstack))
          if (associated(elem)) then
            if (elem%empty) then
              call add_error(fx%error_stack, "Content inside empty element")
            endif
          endif
        endif

        select case(fx%tokenType)
        case (TOK_CHAR)
          if (present(processingInstruction_handler)) then
            call processingInstruction_handler(str_vs(fx%name), str_vs(fx%token))
            if (fx%state==ST_STOP) goto 100
          endif
          deallocate(fx%name)
          nextState = ST_PI_END
        case (TOK_PI_END)
          if (present(processingInstruction_handler)) then
            call processingInstruction_handler(str_vs(fx%name), '')
            if (fx%state==ST_STOP) goto 100
          endif
          deallocate(fx%name)
          if (fx%context==CTXT_IN_CONTENT) then
            nextState = ST_CHAR_IN_CONTENT
          else
            nextState = ST_MISC
          endif
        end select

      case (ST_PI_END)
        write(*,*)'ST_PI_END'
        select case(fx%tokenType)
        case (TOK_PI_END)
          if (fx%context==CTXT_IN_CONTENT) then
            nextState = ST_CHAR_IN_CONTENT
          elseif (fx%context==CTXT_IN_DTD) then
            nextState = ST_SUBSET
          else
            nextState = ST_MISC
          endif
        end select

      case (ST_START_COMMENT)
        !write(*,*)'ST_START_COMMENT'
        select case (fx%tokenType)
        case (TOK_CHAR)
          fx%name => fx%token
          nullify(fx%token)
          nextState = ST_COMMENT_END
        end select

      case (ST_COMMENT_END)
        write(*,*)'ST_COMMENT_END'
        if (validCheck.and.len(fx%elstack)>0) then
          elem => get_element(fx%xds%element_list, get_top_elstack(fx%elstack))
          if (associated(elem)) then
            if (elem%empty) then
              call add_error(fx%error_stack, "Content inside empty element")
            endif
          endif
        endif

        select case (fx%tokenType)
        case (TOK_COMMENT_END)
          if (present(comment_handler)) then
            call comment_handler(str_vs(fx%name))
            if (fx%state==ST_STOP) goto 100
          endif
          deallocate(fx%name)
          if (fx%context==CTXT_IN_CONTENT) then
            nextState = ST_CHAR_IN_CONTENT
          elseif (fx%context==CTXT_IN_DTD) then
            nextState = ST_SUBSET
          else
            nextState = ST_MISC
          endif
        end select

      case (ST_START_TAG)
        write(*,*)'ST_START_TAG', fx%context
        select case (fx%tokenType)
        case (TOK_NAME)
          if (fx%context==CTXT_BEFORE_DTD &
            .or. fx%context==CTXT_BEFORE_CONTENT &
            .or. fx%context==CTXT_IN_CONTENT) then
            if (namespaces_) then
              nameOk = checkQName(str_vs(fx%token), fx%xds)
            else
              nameOk = checkName(str_vs(fx%token), fx%xds)
            endif
            if (.not.nameOk) then
              call add_error(fx%error_stack, "Illegal element name")
              goto 100
            endif
            fx%name => fx%token
            nullify(fx%token)
            nextState = ST_IN_TAG
          elseif (fx%context == CTXT_AFTER_CONTENT) then
            call add_error(fx%error_stack, "Cannot open second root element")
            goto 100
          elseif (fx%context == CTXT_IN_DTD) then
            call add_error(fx%error_stack, "Cannot open root element before DTD is finished")
            goto 100
          endif
        end select

      case (ST_START_SECTION_DECLARATION)
        write(*,*) "ST_START_SECTION_DECLARATION"
        select case (fx%tokenType)
        case (TOK_NAME)
          if (str_vs(fx%token)=="CDATA") then
            if (fx%context/=CTXT_IN_CONTENT) then
              call add_error(fx%error_stack, "CDATA section only allowed in text content.")
              goto 100
            else
              nextState = ST_FINISH_CDATA_DECLARATION
            endif
          elseif (str_vs(fx%token)=="IGNORE") then
            if (fx%context/=CTXT_IN_DTD.or.reading_main_file(fb)) then
              call add_error(fx%error_stack, "IGNORE section only allowed in external subset.")
              goto 100
            else
              section_depth = section_depth + 1
              fx%context = CTXT_IGNORE
              nextState = ST_FINISH_SECTION_DECLARATION
            endif
          elseif (str_vs(fx%token)=="INCLUDE") then
            if (fx%context/=CTXT_IN_DTD.or.reading_main_file(fb)) then
              call add_error(fx%error_stack, "INCLUDE section only allowed in external subset.")
              goto 100
            else
              section_depth = section_depth + 1
              nextState = ST_FINISH_SECTION_DECLARATION
            endif
          else
            call add_error(fx%error_stack, "Unknown keyword found in marked section declaration.")
          endif
        end select

      case (ST_FINISH_CDATA_DECLARATION)
        write(*,*) "ST_FINISH_CDATA_DECLARATION"
        select case (fx%tokenType)
        case (TOK_OPEN_SB)
          nextState = ST_CDATA_CONTENTS
        end select

      case (ST_FINISH_SECTION_DECLARATION)
        write(*,*) "ST_FINISH_CDATA_DECLARATION"
        select case (fx%tokenType)
        case (TOK_OPEN_SB)
          if (fx%context==CTXT_IGNORE) then
            nextState = ST_IN_IGNORE_SECTION
          else
            nextState = ST_SUBSET
          endif
        end select

      case (ST_IN_IGNORE_SECTION)
        write(*,*) "ST_IN_IGNORE_SECTION"
        select case (fx%tokenType)
        case (TOK_SECTION_START)
          section_depth = section_depth + 1
          nextState = ST_IN_IGNORE_SECTION
        case (TOK_SECTION_END)
          section_depth = section_depth - 1
          if (section_depth==0) then
            fx%context = CTXT_IN_DTD
            nextState = ST_SUBSET
          else
            nextState = ST_IN_IGNORE_SECTION
          endif
        end select

      case (ST_CDATA_CONTENTS)
        write(*,*)'ST_CDATA_CONTENTS'
        select case (fx%tokenType)
        case (TOK_CHAR)
          fx%name => fx%token
          nullify(fx%token)
          nextState = ST_CDATA_END
        end select

      case (ST_CDATA_END)
        write(*,*)'ST_CDATA_END'
        if (validCheck) then
          elem => get_element(fx%xds%element_list, get_top_elstack(fx%elstack))
          if (associated(elem)) then
            if (elem%empty) then
              call add_error(fx%error_stack, "Content inside empty element")
              goto 100
            elseif (.not.elem%mixed.and..not.elem%any) then
              ! NB even whitespace-only CDATA section forbidden
              ! FIXME but is an empty CDATA section allowed?
              call add_error(fx%error_stack, "Forbidden content inside element")
              goto 100
            endif
          endif
        endif

        select case(fx%tokenType)
        case (TOK_SECTION_END)
          if (present(startCdata_handler)) then
            call startCdata_handler
            if (fx%state==ST_STOP) goto 100
          endif
          if (size(fx%name)>0) then
            if (present(characters_handler)) then
              call characters_handler(str_vs(fx%name))
              if (fx%state==ST_STOP) goto 100
            endif
          endif
          if (present(endCdata_handler)) then
            call endCdata_handler
            if (fx%state==ST_STOP) goto 100
          endif
          deallocate(fx%name)
          nextState = ST_CHAR_IN_CONTENT
        end select

      case (ST_IN_TAG)
        write(*,*)'ST_IN_TAG'
        select case (fx%tokenType)
        case (TOK_END_TAG)
          if (fx%context /= CTXT_IN_CONTENT) then
            if (associated(fx%root_element)) then
              if (validCheck) then
                if (str_vs(fx%name)/=str_vs(fx%root_element)) then
                  call add_error(fx%error_stack, "Root element name does not match document name")
                  goto 100
                endif
              endif
              deallocate(fx%root_element)
            elseif (validCheck) then
              call add_error(fx%error_stack, "No DTD defined")
              goto 100
            endif
            ! This is the root node, so we've finished populating
            ! the xml_doc_state. Hand it over to DOM if necessary:
            ! Here we hand over responsibility for the xds object
            ! The SAX caller must take care of it, and we don't
            ! need it any more. (We will destroy it shortly anyway)
            if (present(FoX_endDTD_handler)) then
              fx%xds_used = .true.
              call FoX_endDTD_handler(fx%xds)
            endif
            fx%context = CTXT_IN_CONTENT
          endif
          call open_tag
          if (in_error(fx%error_stack)) goto 100
          deallocate(fx%name)
          nextState = ST_CHAR_IN_CONTENT

        case (TOK_END_TAG_CLOSE)
          if (fx%context==CTXT_IN_CONTENT) then
            nextState = ST_CHAR_IN_CONTENT
          else
            ! only a single element in this doc
            if (associated(fx%root_element)) then
              if (validCheck) then
                if (str_vs(fx%name)/=str_vs(fx%root_element)) then
                  call add_error(fx%error_stack, "Root element name does not match document name")
                  goto 100
                endif
              endif
              deallocate(fx%root_element)
            elseif (validCheck) then
              call add_error(fx%error_stack, "No DTD defined")
              goto 100
            endif
            ! This is the root node, so we've finished populating
            ! the xml_doc_state. Hand it over to DOM if necessary:
            ! Here we hand over responsibility for the xds object
            ! The SAX caller must take care of it, and we don't
            ! need it any more. (We will destroy it shortly anyway)
            if (present(FoX_endDTD_handler)) then
              fx%xds_used = .true.
              call FoX_endDTD_handler(fx%xds)
            endif
          endif
          call open_tag
          if (in_error(fx%error_stack)) goto 100
          call close_tag
          if (in_error(fx%error_stack)) goto 100
          deallocate(fx%name)
          if (fx%context/=CTXT_IN_CONTENT) then
            fx%well_formed = .true.
            fx%context = CTXT_AFTER_CONTENT
            nextState = ST_MISC
          endif

        case (TOK_NAME)
          if (namespaces_) then
            nameOk = checkQName(str_vs(fx%token), fx%xds)
          else
            nameOk = checkName(str_vs(fx%token), fx%xds)
          endif
          if (.not.nameOk) then
            call add_error(fx%error_stack, "Illegal attribute name")
            goto 100
          endif
          !Have we already had this dictionary item?
          if (has_key(fx%attributes, str_vs(fx%token))) then
            call add_error(fx%error_stack, "Duplicate attribute name")
            goto 100
          endif
          fx%attname => fx%token
          nullify(fx%token)
          nextState = ST_ATT_NAME
        end select

      case (ST_ATT_NAME)
        write(*,*)'ST_ATT_NAME'
        select case (fx%tokenType)
        case (TOK_EQUALS)
          nextState = ST_ATT_EQUALS
        end select

      case (ST_ATT_EQUALS)
        write(*,*)'ST_ATT_EQUALS'
        ! token is pre-processed attribute value.
        ! fx%name still contains attribute name
        select case (fx%tokenType)
        case (TOK_CHAR)
          !First, expand all entities:
          tempString => normalize_text(fx, fx%token)
          deallocate(fx%token)
          fx%token => tempString
          nullify(tempString)
          !If this attribute is not CDATA, we must process further;
          temp_i = get_att_type(fx%xds%element_list, str_vs(fx%name), str_vs(fx%attname))
          if (temp_i==ATT_CDATA) then
            call add_item_to_dict(fx%attributes, str_vs(fx%attname), &
              str_vs(fx%token), itype=ATT_CDATA)
          else
            call add_item_to_dict(fx%attributes, str_vs(fx%attname), &
              trim(NotCDataNormalize(str_vs(fx%token))), itype=temp_i)
          endif
          deallocate(fx%attname)
          nextState = ST_IN_TAG
        end select

      case (ST_CHAR_IN_CONTENT)
        write(*,*)'ST_CHAR_IN_CONTENT'
        select case (fx%tokenType)
        case (TOK_CHAR)
          if (size(fx%token)>0) then
            if (validCheck) then
              elem => get_element(fx%xds%element_list, get_top_elstack(fx%elstack))
              if (associated(elem)) then
                if (elem%empty) then
                  call add_error(fx%error_stack, "Content inside empty element")
                  goto 100
                elseif (.not.elem%mixed.and..not.elem%any) then
                  if (verify(str_vs(fx%token), XML_WHITESPACE)==0) then
                    if (present(ignorableWhitespace_handler)) then
                      call ignorableWhitespace_handler(str_vs(fx%token))
                      if (fx%state==ST_STOP) goto 100
                    endif
                  else
                    call add_error(fx%error_stack, "Forbidden content inside element: "//get_top_elstack(fx%elstack))
                    goto 100
                  endif
                else ! FIXME check properly if allowed
                  if (present(characters_handler)) then
                    call characters_handler(str_vs(fx%token))
                    goto 100
                  endif
                endif
              endif
            else
              if (present(characters_handler)) then
                call characters_handler(str_vs(fx%token))
                if (fx%state==ST_STOP) goto 100
              endif
            endif
          endif
          nextState = ST_TAG_IN_CONTENT
        end select

      case (ST_TAG_IN_CONTENT)
        write(*,*) 'ST_TAG_IN_CONTENT'
        select case (fx%tokenType)
        case (TOK_ENTITY)
          nextState = ST_START_ENTITY
        case (TOK_PI_TAG)
          nextState = ST_START_PI
        case (TOK_BANG_TAG)
          nextState = ST_BANG_TAG
        case (TOK_CLOSE_TAG)
          nextState = ST_CLOSING_TAG
        case (TOK_OPEN_TAG)
          nextState = ST_START_TAG
        end select

      case (ST_START_ENTITY)
        write(*,*) 'ST_START_ENTITY'
        select case (fx%tokenType)
        case (TOK_NAME)
          print*, "starting with the entity ..."
          if (validCheck) &
            elem => get_element(fx%xds%element_list, get_top_elstack(fx%elstack))
          ! tell tokenizer to expand it
          print*, "checking forbidden list"
          if (existing_entity(fx%forbidden_ge_list, str_vs(fx%token))) then
            call add_error(fx%error_stack, 'Recursive entity reference')
	    goto 100
          endif
          if (existing_entity(fx%predefined_e_list, str_vs(fx%token))) then
            if (validCheck.and.associated(elem)) then
              if (.not.elem%mixed.and..not.elem%any) then
                call add_error(fx%error_stack, "Forbidden content inside element")
                goto 100
              endif
            else
              call add_error(fx%error_stack, &
                'Encountered reference to undeclared entity')
            endif
            if (present(startEntity_handler)) then
              call startEntity_handler(str_vs(fx%token))
              if (fx%state==ST_STOP) goto 100
            endif
            if (present(characters_handler)) then
              call characters_handler(expand_entity(fx%predefined_e_list, str_vs(fx%token)))
              if (fx%state==ST_STOP) goto 100
            endif
            if (present(endEntity_handler)) then
              call endEntity_handler(str_vs(fx%token))
              if (fx%state==ST_STOP) goto 100
            endif
          elseif (likeCharacterEntityReference(str_vs(fx%token))) then
            if (checkRepCharEntityReference(str_vs(fx%token), fx%xds%xml_version)) then
              if (validCheck.and.associated(elem)) then
                if (elem%empty) then
                  call add_error(fx%error_stack, "Forbidden content inside element")
                  goto 100
                elseif (.not.elem%mixed.and..not.elem%any) then
                  call add_error(fx%error_stack, "Forbidden content inside element")
                  goto 100 
                endif
              endif
              if (present(characters_handler)) then
                call characters_handler(expand_char_entity(str_vs(fx%token)))
                if (fx%state==ST_STOP) goto 100
              endif
            elseif (checkCharacterEntityReference(str_vs(fx%token), fx%xds%xml_version)) then
              call add_error(fx%error_stack, "Unable to digest character entity reference in content, sorry.")
              goto 100
            else
              call add_error(fx%error_stack, "Illegal character reference")
              goto 100
            endif
          elseif (existing_entity(fx%xds%entityList, str_vs(fx%token))) then
            ent => getEntityByName(fx%xds%entityList, str_vs(fx%token))
            print*, "is existing entity ", ent%external, str_vs(ent%systemId)
            if (str_vs(ent%notation)/="") then
              call add_error(fx%error_stack, &
                'Cannot reference unparsed entity in content')
              goto 100
            elseif (ent%external) then
              call open_new_file(fb, str_vs(ent%systemId), iostat)
              print*, "new file opened"
              if (iostat/=0) then
                if (present(skippedEntity_handler)) then
                  call skippedEntity_handler(str_vs(fx%token))
                  if (fx%state==ST_STOP) goto 100
                endif
              else
                if (present(startEntity_handler)) then
                  call startEntity_handler(str_vs(fx%token))
                  if (fx%state==ST_STOP) goto 100
                endif
                call add_internal_entity(fx%forbidden_ge_list, str_vs(fx%token), "")
                temp_wf_stack => fx%wf_stack
                allocate(fx%wf_stack(size(temp_wf_stack)+1))
                fx%wf_stack(2:size(fx%wf_stack)) = temp_wf_stack
                fx%wf_stack(1) = 0
                deallocate(temp_wf_stack)
                call parse_text_declaration(fb, fx%error_stack)
                if (in_error(fx%error_stack)) goto 100
              endif
            else
              if (validCheck.and.associated(elem)) then
                if (elem%empty) then
                  call add_error(fx%error_stack, "Forbidden content inside element")
                  goto 100
                  !elseif (.not.elem%mixed.and..not.elem%any) then FIXME
                  !c1 = getEntityTextByName(fx%xds%entityList, str_vs(tempString)
                  !if (verify(getEntityTextByName(fx%xds%entityList, str_vs(tempString)), XML_WHITESPACE)/=0 & 
                  !.and. c1/="<") then
                  !call add_error(fx%error_stack, "Forbidden content inside element")
                  !goto 100
                  !endif
                endif
              endif
              if (present(startEntity_handler)) &
                call startEntity_handler(str_vs(fx%token))
              print*, "adding to forbidden list"
              call add_internal_entity(fx%forbidden_ge_list, str_vs(fx%token), "")
              print*, "adding to buffer stack", expand_entity(fx%xds%entityList, str_vs(fx%token))
              call open_new_string(fb, expand_entity(fx%xds%entityList, str_vs(fx%token)))
              temp_wf_stack => fx%wf_stack
              allocate(fx%wf_stack(size(temp_wf_stack)+1))
              fx%wf_stack(2:size(fx%wf_stack)) = temp_wf_stack
              fx%wf_stack(1) = 0
              deallocate(temp_wf_stack)
            endif
          else
            ! Unknown entity check standalone etc
            if (fx%skippedExternal.and..not.fx%xds%standalone) then
              if (present(skippedEntity_handler)) then
                call skippedEntity_handler(str_vs(fx%token))
                if (fx%state==ST_STOP) goto 100
              endif
            else
              call add_error(fx%error_stack, &
                'Encountered reference to undeclared entity')
            endif
          endif
          nextState = ST_CHAR_IN_CONTENT ! FIXME
          print*, "ok?"
        end select

      case (ST_CLOSING_TAG)
        write(*,*)'ST_CLOSING_TAG'
        select case (fx%tokenType)
        case (TOK_NAME)
          if (checkName(str_vs(fx%token), fx%xds)) then
            fx%name => fx%token
            nullify(fx%token)
            nextState = ST_IN_CLOSING_TAG
          else
            call add_error(fx%error_stack, "Closing tag: expecting a Name")
            goto 100
          end if
        end select

      case (ST_IN_CLOSING_TAG)
        write(*,*)'ST_IN_CLOSING_TAG'
        select case (fx%tokenType)
        case (TOK_END_TAG)
          call close_tag
          if (in_error(fx%error_stack)) goto 100
          deallocate(fx%name)
          if (is_empty(fx%elstack)) then
            if (startInCharData_) then
              fx%well_formed = .true.
              nextState = ST_CHAR_IN_CONTENT
            else
              !we're done
              fx%well_formed = .true.
              nextState = ST_MISC
              fx%context = CTXT_AFTER_CONTENT
            endif
          else
            nextState = ST_CHAR_IN_CONTENT
          endif
        end select

      case (ST_IN_DTD)
        write(*,*)'ST_IN_DTD'
        select case (fx%tokenType)
        case (TOK_NAME)
          if (namespaces_) then
            nameOk = checkQName(str_vs(fx%token), fx%xds)
          else
            nameOk = checkName(str_vs(fx%token), fx%xds)
          endif
          if (.not.nameOk) then
            call add_error(fx%error_stack, "Invalid document name")
            goto 100
          endif
          fx%root_element => fx%token
          nullify(fx%token)
          nextState = ST_DTD_NAME
        end select

      case (ST_DTD_NAME)
        write(*,*) 'ST_DTD_NAME ', str_vs(fx%token)
        select case (fx%tokenType)
        case (TOK_NAME)
          if (str_vs(fx%token)=='SYSTEM') then
            nextState = ST_DTD_SYSTEM
          elseif (str_vs(fx%token)=='PUBLIC') then
            nextState = ST_DTD_PUBLIC
          endif
        case (TOK_OPEN_SB)
          if (present(startDTD_handler)) then
            call startDTD_handler(str_vs(fx%root_element), "", "")
            if (fx%state==ST_STOP) goto 100
          endif
          nextState = ST_SUBSET
        case (TOK_END_TAG)
          if (present(startDTD_handler)) then
            call startDTD_handler(str_vs(fx%root_element), "", "")
            if (fx%state==ST_STOP) goto 100
          endif
          fx%context = CTXT_BEFORE_CONTENT
          nextState = ST_MISC
        case default
          call add_error(fx%error_stack, "Unexpected token")
          goto 100
        end select

      case (ST_DTD_PUBLIC)
        write(*,*) 'ST_DTD_PUBLIC'
        select case (fx%tokenType)
        case (TOK_CHAR)
          if (checkPublicId(str_vs(fx%token))) then
            fx%publicId => fx%token
            fx%token => null()
            nextState = ST_DTD_SYSTEM
          else
            call add_error(fx%error_stack, "Invalid document public id")
            goto 100
          endif
        end select

      case (ST_DTD_SYSTEM)
        write(*,*) 'ST_DTD_SYSTEM'
        select case (fx%tokenType)
        case (TOK_CHAR)
          fx%systemId => fx%token
          fx%token => null()
          nextState = ST_DTD_DECL
        end select

      case (ST_DTD_DECL)
        write(*,*) 'ST_DTD_DECL'
        select case (fx%tokenType)
        case (TOK_OPEN_SB)
          if (associated(fx%publicId).or.associated(fx%systemId)) &
            fx%skippedExternal = .true.
          if (present(startDTD_handler)) then
            if (associated(fx%publicId)) then
              call startDTD_handler(str_vs(fx%root_element), publicId=str_vs(fx%publicId), systemId=str_vs(fx%systemId))
            elseif (associated(fx%systemId)) then
              call startDTD_handler(str_vs(fx%root_element), publicId="", systemId=str_vs(fx%systemId))
            else
              call startDTD_handler(str_vs(fx%root_element), "", "")
            endif
            if (fx%state==ST_STOP) goto 100
          endif
          if (associated(fx%systemId)) deallocate(fx%systemId)
          if (associated(fx%publicId)) deallocate(fx%publicId)
          nextState = ST_SUBSET
        case (TOK_END_TAG)
          if (associated(fx%systemId)) then
            URIref => parseURI(str_vs(fx%systemId))
            if (.not.associated(URIref)) then
              call add_error(fx%error_stack, "Invalid URI specified for DTD SYSTEM")
              goto 100
            endif
            ! if we can, then go & get external subset ...
            ! else
            fx%skippedExternal = .true.
            ! endif
          endif
          if (present(startDTD_handler)) then
            if (associated(fx%publicId)) then
              call startDTD_handler(str_vs(fx%root_element), publicId=str_vs(fx%publicId), systemId=str_vs(fx%systemId))
              deallocate(fx%publicId)
            elseif (associated(fx%systemId)) then
              call startDTD_handler(str_vs(fx%root_element), publicId="", systemId=str_vs(fx%systemId))
            else
              call startDTD_handler(str_vs(fx%root_element), "", "")
            endif
            if (fx%state==ST_STOP) goto 100
          endif
          if (associated(fx%systemId)) deallocate(fx%systemId)
          if (associated(fx%publicId)) deallocate(fx%publicId)
          if (present(endDTD_handler)) &
            call endDTD_handler

          fx%context = CTXT_BEFORE_CONTENT
          nextState = ST_MISC
        case default
          call add_error(fx%error_stack, "Unexpected token in DTD")
          goto 100
        end select

      case (ST_SUBSET)
        write(*,*) "ST_SUBSET"
        select case (fx%tokenType)
        case (TOK_CLOSE_SB)
          nextState = ST_CLOSE_DTD
        case (TOK_SECTION_END)
          if (section_depth>0) then
            section_depth = section_depth - 1
            nextState = ST_SUBSET
          else
            call add_error(fx%error_stack, "Trying to close a conditional section which is not open")
            goto 100
          endif
          nextState = ST_SUBSET
        case (TOK_ENTITY)
          nextState = ST_START_PE
        case (TOK_PI_TAG)
          nextState = ST_START_PI
        case (TOK_BANG_TAG)
          nextState = ST_BANG_TAG
        case default
          call add_error(fx%error_stack, "Unexpected token in internal subset")
          goto 100
        end select

      case (ST_START_PE)
        write(*,*) 'ST_START_PE'
        select case (fx%tokenType)
        case (TOK_NAME)
          if (existing_entity(fx%forbidden_pe_list, str_vs(fx%token))) then
            call add_error(fx%error_stack, &
              'Recursive entity reference')
            goto 100
          endif
          ent => getEntityByName(fx%xds%PEList, str_vs(fx%token))
          if (associated(ent)) then
            if (ent%external) then
              if (present(startEntity_handler)) then
                call startEntity_handler('%'//str_vs(fx%token))
                if (fx%state==ST_STOP) goto 100
              endif
              call add_internal_entity(fx%forbidden_pe_list, &
                str_vs(fx%token), "")
              call open_new_file(fb, str_vs(ent%systemId), iostat)
              if (iostat/=0) then
                if (present(skippedEntity_handler)) then
                  call skippedEntity_handler('%'//str_vs(fx%token))
                  if (fx%state==ST_STOP) goto 100
                endif
                ! having skipped a PE, we must now not process
                ! declarations any further (unless we are declared standalone)
                ! (XML section 5.1)
                fx%skippedExternal = .true.
                processDTD = fx%xds%standalone
              else
                if (present(startEntity_handler)) then
                  call startEntity_handler('%'//str_vs(fx%token))
                  if (fx%state==ST_STOP) goto 100
                endif
                call add_internal_entity(fx%forbidden_pe_list, &
                  str_vs(fx%token), "")
                call parse_text_declaration(fb, fx%error_stack)
                if (in_error(fx%error_stack)) goto 100
              endif
            else
              ! Expand the entity, 
              if (present(startEntity_handler)) then
                call startEntity_handler('%'//str_vs(fx%token))
                if (fx%state==ST_STOP) goto 100	
              endif
              call add_internal_entity(fx%forbidden_pe_list, &
                str_vs(fx%token), "")
              call open_new_string(fb, &
                " "//expand_entity(fx%xds%PEList, str_vs(fx%token))//" ")
            endif
            ! and do nothing else, carry on ...
          else
            ! Have we previously skipped an external entity?
            if (fx%skippedExternal.and..not.fx%xds%standalone) then
              if (processDTD) then
                if (present(skippedEntity_handler)) then
                  call skippedEntity_handler('%'//str_vs(fx%token))
                  if (fx%state==ST_STOP) goto 100
                endif
              endif
            else
              ! If not, 
              call add_error(fx%error_stack, &
                "Reference to undeclared parameter entity.")
              goto 100
            endif
          endif
          nextState = ST_SUBSET
        end select

      case (ST_DTD_ATTLIST)
        write(*,*) 'ST_DTD_ATTLIST'
        select case (fx%tokenType)
        case (TOK_NAME)
          if (namespaces_) then
            nameOk = checkQName(str_vs(fx%token), fx%xds)
          else
            nameOk = checkName(str_vs(fx%token), fx%xds)
          endif
          if (.not.nameOk) then
            call add_error(fx%error_stack, "Invalid element name for ATTLIST")
            goto 100
          endif
          if (existing_element(fx%xds%element_list, str_vs(fx%token))) then
            elem => get_element(fx%xds%element_list, str_vs(fx%token))
          else
            elem => add_element(fx%xds%element_list, str_vs(fx%token))
          endif
          nextState = ST_DTD_ATTLIST_CONTENTS
        end select

      case (ST_DTD_ATTLIST_CONTENTS)
        write(*,*) 'ST_DTD_ATTLIST_CONTENTS'
        select case (fx%tokenType)
        case (TOK_DTD_CONTENTS)
          if (processDTD) then
            call parse_dtd_attlist(str_vs(fx%token), fx%xds%xml_version, fx%error_stack, elem)
          else
            call parse_dtd_attlist(str_vs(fx%token), fx%xds%xml_version, fx%error_stack)
          endif
          if (in_error(fx%error_stack)) goto 100
          ! Normalize attribute values in attlist
          if (processDTD) then
            do i = 1, size(elem%attlist%list)
              if (associated(elem%attlist%list(i)%default)) then
                tempString => elem%attlist%list(i)%default
                elem%attlist%list(i)%default => normalize_text(fx, tempString)
                deallocate(tempString)
                if (in_error(fx%error_stack)) goto 100
              endif
            enddo
          endif
          nextState = ST_DTD_ATTLIST_END
        case (TOK_END_TAG)
          if (processDTD) then
            call parse_dtd_attlist("", fx%xds%xml_version, fx%error_stack, elem)
          else
            call parse_dtd_attlist("", fx%xds%xml_version, fx%error_stack)
          endif
          if (in_error(fx%error_stack)) goto 100
          if (processDTD) then
            if (present(attributeDecl_handler)) &
              call report_declarations(elem, attributeDecl_handler)
          endif
          nextState = ST_SUBSET
        end select

      case (ST_DTD_ATTLIST_END)
        write(*,*) 'ST_DTD_ATTLIST_END'
        select case (fx%tokenType)
        case (TOK_END_TAG)
          if (processDTD) then
            if (present(attributeDecl_handler)) then
              call report_declarations(elem, attributeDecl_handler)
              if (fx%state==ST_STOP) goto 100
            endif
          endif
          nextState = ST_SUBSET
        end select

      case (ST_DTD_ELEMENT)
        select case (fx%tokenType)
        case (TOK_NAME)
          if (namespaces_) then
            nameOk = checkQName(str_vs(fx%token), fx%xds)
          else
            nameOk = checkName(str_vs(fx%token), fx%xds)
          endif
          if (.not.nameOk) then
            call add_error(fx%error_stack, "Invalid name for ELEMENT")
            goto 100
          endif
          fx%name => fx%token
          fx%token => null()
          nextState = ST_DTD_ELEMENT_CONTENTS
        end select

      case (ST_DTD_ELEMENT_CONTENTS)
        write(*,*)'ST_DTD_ELEMENT_CONTENTS'
        select case (fx%tokenType)
        case (TOK_DTD_CONTENTS)
          if (declared_element(fx%xds%element_list, str_vs(fx%name))) then
            if (validCheck) then
              call add_error(fx%error_stack, "Duplicate Element declaration")
              goto 100
            else
              ! Ignore contents ...
              elem => null()
            endif
          elseif (processDTD) then
            if (existing_element(fx%xds%element_list, str_vs(fx%name))) then
              elem => get_element(fx%xds%element_list, str_vs(fx%name))
            else
              elem => add_element(fx%xds%element_list, str_vs(fx%name))
            endif
          else
            elem => null()
          endif
          call parse_dtd_element(str_vs(fx%token), fx%xds%xml_version, fx%error_stack, elem)
          if (in_error(fx%error_stack)) goto 100
          nextState = ST_DTD_ELEMENT_END
        end select

      case (ST_DTD_ELEMENT_END)
        write(*,*)'ST_DTD_ELEMENT_END'
        select case (fx%tokenType)
        case (TOK_END_TAG)
          if (processDTD.and.associated(elem)) then
            if (present(elementDecl_handler)) then
              call elementDecl_handler(str_vs(fx%name), str_vs(elem%model))
              if (fx%state==ST_STOP) goto 100
            endif
          endif
          deallocate(fx%name)
          nextState = ST_SUBSET
        end select

      case (ST_DTD_ENTITY)
        write(*,*) 'ST_DTD_ENTITY'
        select case (fx%tokenType)
        case (TOK_ENTITY)
          pe = .true.
          ! this will be a PE
          nextState = ST_DTD_ENTITY_PE
        case (TOK_NAME)
          pe = .false.
          if (namespaces_) then
            nameOk = checkNCName(str_vs(fx%token), fx%xds)
          else
            nameOk = checkName(str_vs(fx%token), fx%xds)
          endif
          if (.not.nameOk) then
            call add_error(fx%error_stack, &
              "Illegal name for general entity")
            goto 100
          endif
          fx%name => fx%token
          fx%token => null()
          nextState = ST_DTD_ENTITY_ID
        end select

      case (ST_DTD_ENTITY_PE)
        write(*,*) 'ST_DTD_ENTITY_PE'
        select case (fx%tokenType)
        case (TOK_NAME)
          if (namespaces_) then
            nameOk = checkNCName(str_vs(fx%token), fx%xds)
          else
            nameOk = checkName(str_vs(fx%token), fx%xds)
          endif
          if (.not.nameOk) then
            call add_error(fx%error_stack, &
              "Illegal name for parameter entity")
            goto 100
          endif
          fx%name => fx%token
          fx%token => null()
          nextState = ST_DTD_ENTITY_ID
        end select

      case (ST_DTD_ENTITY_ID)
        write(*,*) 'ST_DTD_ENTITY_ID'
        select case (fx%tokenType)
        case (TOK_NAME)
          if (str_vs(fx%token) == "PUBLIC") then
            nextState = ST_DTD_ENTITY_PUBLIC
          elseif (str_vs(fx%token) == "SYSTEM") then
            nextState = ST_DTD_ENTITY_SYSTEM
          else
            call add_error(fx%error_stack, "Unexpected token in ENTITY")
            goto 100
          endif
        case (TOK_CHAR)
          fx%attname => expand_entity_value_alloc(fx%token, fx%xds, fx%error_stack)
          if (in_error(fx%error_stack)) goto 100
          nextState = ST_DTD_ENTITY_END
        case default
          call add_error(fx%error_stack, "Unexpected token in ENTITY")
          goto 100
        end select

      case (ST_DTD_ENTITY_PUBLIC)
        write(*,*) 'ST_DTD_ENTITY_PUBLIC'
        select case (fx%tokenType)
        case (TOK_CHAR)
          if (checkPublicId(str_vs(fx%token))) then
            fx%publicId => fx%token
            fx%token => null()
            nextState = ST_DTD_ENTITY_SYSTEM
          else
            call add_error(fx%error_stack, "Invalid PUBLIC id in ENTITY")
            goto 100
          endif
        case default
          call add_error(fx%error_stack, "Unexpected token in ENTITY")
          goto 100
        end select

      case (ST_DTD_ENTITY_SYSTEM)
        write(*,*) 'ST_DTD_ENTITY_SYSTEM'
        select case (fx%tokenType)
        case (TOK_CHAR)
          fx%systemId => fx%token
          fx%token => null()
          nextState = ST_DTD_ENTITY_NDATA
        case default
          call add_error(fx%error_stack, "Unexpected token in ENTITY")
          goto 100
        end select

      case (ST_DTD_ENTITY_NDATA)
        write(*,*) 'ST_DTD_ENTITY_NDATA'
        select case (fx%tokenType)
        case (TOK_END_TAG)
          if (processDTD) then
            call add_entity
            if (in_error(fx%error_stack)) goto 100
          endif
          deallocate(fx%name)
          if (associated(fx%attname)) deallocate(fx%attname)
          if (associated(fx%systemId)) deallocate(fx%systemId)
          if (associated(fx%publicId)) deallocate(fx%publicId)
          if (associated(fx%Ndata)) deallocate(fx%Ndata)
          nextState = ST_SUBSET
        case (TOK_NAME)
          if (str_vs(fx%token)=='NDATA') then
            if (pe) then
              call add_error(fx%error_stack, "Parameter entity cannot have NDATA declaration")
              goto 100
            endif
            nextState = ST_DTD_ENTITY_NDATA_VALUE
          else
            call add_error(fx%error_stack, "Unexpected token in ENTITY")
            goto 100
          endif
        case default
          call add_error(fx%error_stack, "Unexpected token in ENTITY")
          goto 100
        end select

      case (ST_DTD_ENTITY_NDATA_VALUE)
        write(*,*) 'ST_DTD_ENTITY_NDATA_VALUE'
        !check is a name and exists in notationlist
        select case (fx%tokenType)
        case (TOK_NAME)
          if (namespaces_) then
            nameOk = checkNCName(str_vs(fx%token), fx%xds)
          else
            nameOk = checkName(str_vs(fx%token), fx%xds)
          endif
          if (.not.nameOk) then
            call add_error(fx%error_stack, "Invalid name for Notation")
            goto 100
          endif
          fx%Ndata => fx%token
          fx%token => null()
          nextState = ST_DTD_ENTITY_END
        case default
          call add_error(fx%error_stack, "Unexpected token in ENTITY")
          goto 100
        end select

      case (ST_DTD_ENTITY_END)
        write(*,*) 'ST_DTD_ENTITY_END'
        select case (fx%tokenType)
        case (TOK_END_TAG)
          if (processDTD) then
            call add_entity
            if (in_error(fx%error_stack)) goto 100
          endif
          deallocate(fx%name)
          if (associated(fx%attname)) deallocate(fx%attname)
          if (associated(fx%systemId)) deallocate(fx%systemId)
          if (associated(fx%publicId)) deallocate(fx%publicId)
          if (associated(fx%Ndata)) deallocate(fx%Ndata)
          nextState = ST_SUBSET
        case default
          call add_error(fx%error_stack, "Unexpected token at end of ENTITY")
          goto 100
        end select

      case (ST_DTD_NOTATION)
        write(*,*) 'ST_DTD_NOTATION'
        select case (fx%tokenType)
        case (TOK_NAME)
          if (namespaces_) then
            nameOk = checkNCName(str_vs(fx%token), fx%xds)
          else
            nameOk = checkName(str_vs(fx%token), fx%xds)
          endif
          if (.not.nameOk) then
            call add_error(fx%error_stack, "Invalid name for Notation")
            goto 100
          endif
          fx%name => fx%token
          fx%token => null()
          nextState = ST_DTD_NOTATION_ID
        case default
          call add_error(fx%error_stack, "Unexpected token in NOTATION")
          goto 100
        end select

      case (ST_DTD_NOTATION_ID)
        write(*,*)'ST_DTD_NOTATION_ID'
        select case (fx%tokenType)
        case (TOK_NAME)
          if (str_vs(fx%token)=='SYSTEM') then
            nextState = ST_DTD_NOTATION_SYSTEM
          elseif (str_vs(fx%token)=='PUBLIC') then
            nextState = ST_DTD_NOTATION_PUBLIC
          else
            call add_error(fx%error_stack, "Unexpected token after NOTATION")
            goto 100
          endif
        case default
          call add_error(fx%error_stack, "Unexpected token after NOTATION")
          goto 100
        end select

      case (ST_DTD_NOTATION_SYSTEM)
        write(*,*)'ST_DTD_NOTATION_SYSTEM'
        select case (fx%tokenType)
        case (TOK_CHAR)
          fx%systemId => fx%token
          fx%token => null()
          nextState = ST_DTD_NOTATION_END
        case default
          call add_error(fx%error_stack, "Unexpected token in NOTATION")
          goto 100
        end select

      case (ST_DTD_NOTATION_PUBLIC)
        write(*,*)'ST_DTD_NOTATION_PUBLIC'
        select case (fx%tokenType)
        case (TOK_CHAR)
          if (checkPublicId(str_vs(fx%token))) then
            fx%publicId => fx%token
            fx%token => null()
            nextState = ST_DTD_NOTATION_PUBLIC_2
          else
            call add_error(fx%error_stack, "Invalid PUBLIC id in NOTATION")
            goto 100
          endif
        case default
          call add_error(fx%error_stack, "Unexpected token in NOTATION")
          goto 100
        end select

      case (ST_DTD_NOTATION_PUBLIC_2)
        write(*,*)'ST_DTD_NOTATION_PUBLIC_2'
        select case (fx%tokenType)
        case (TOK_END_TAG)
          if (validCheck) then
            if (notation_exists(fx%nlist, str_vs(fx%name))) then
              call add_error(fx%error_stack, "Duplicate notation declaration")
              goto 100
            endif
          endif
          if (processDTD) then
            call add_notation(fx%nlist, str_vs(fx%name), publicId=str_vs(fx%publicId))
            if (present(notationDecl_handler)) then
              call notationDecl_handler(str_vs(fx%name), publicId=str_vs(fx%publicId), systemId="")
              if (fx%state==ST_STOP) goto 100
            endif
          endif
          deallocate(fx%name)
          deallocate(fx%publicId)
          nextState = ST_SUBSET
        case (TOK_CHAR)
          fx%systemId => fx%token
          fx%token => null()
          nextState = ST_DTD_NOTATION_END
        end select

      case (ST_DTD_NOTATION_END)
        write(*,*)'ST_DTD_NOTATION_END'
        select case (fx%tokenType)
        case (TOK_END_TAG)
          if (validCheck) then
            if (notation_exists(fx%nlist, str_vs(fx%name))) then
              call add_error(fx%error_stack, "Duplicate notation declaration")
              goto 100
            endif
          endif
          if (processDTD) then
            if (associated(fx%publicId)) then
              call add_notation(fx%nlist, str_vs(fx%name), &
                publicId=str_vs(fx%publicId), systemId=str_vs(fx%systemId))
              if (present(notationDecl_handler)) then
                call notationDecl_handler(str_vs(fx%name), &
                publicId=str_vs(fx%publicId), systemId=str_vs(fx%systemId))
                if (fx%state==ST_STOP) goto 100
              endif
            else
              call add_notation(fx%nlist, str_vs(fx%name), &
                systemId=str_vs(fx%systemId))
              if (present(notationDecl_handler)) then
                call notationDecl_handler(str_vs(fx%name), &
                publicId="", systemId=str_vs(fx%systemId))
                if (fx%state==ST_STOP) goto 100
              endif
            endif
          endif
          if (associated(fx%publicId)) deallocate(fx%publicId)
          deallocate(fx%systemId)
          deallocate(fx%name)
          nextState = ST_SUBSET
        case default
          call add_error(fx%error_stack, "Unexpected token in NOTATION")
          goto 100
        end select

      case (ST_CLOSE_DTD)
        write(*,*) "ST_CLOSE_DTD"
        select case (fx%tokenType)
        case (TOK_END_TAG)
          if (section_depth/=0) then
            call add_error(fx%error_stack, "Cannot end DTD while conditional section is still open")
            goto 100
          endif
          if (present(endDTD_handler)) &
            call endDTD_handler
          ! Check that all notations used have been declared:
          if (validCheck) then
            do i = 1, size(fx%xds%entityList)
              ent => getEntityByIndex(fx%xds%entityList, i)
              if (str_vs(ent%notation)/="" &
                .and..not.notation_exists(fx%nlist, str_vs(ent%notation))) then
                call add_error(fx%error_stack, "Attempt to use undeclared notation")
                goto 100
              endif
            enddo
          endif
          nextState = ST_MISC
          fx%context = CTXT_BEFORE_CONTENT
        end select


      end select

      if (nextState/=ST_NULL) then
        fx%state = nextState
        print*, "newState: ", fx%state
      else
        call add_error(fx%error_stack, "Internal error in parser - no suitable token found")
        goto 100
      endif

    end do

100 if (associated(tempString)) deallocate(tempString)

    if (.not.eof) then
      ! We have encountered an error before the end of a file
      if (.not.reading_main_file(fb)) then !we are parsing an entity
        call add_error(fx%error_stack, "Error encountered processing entity.")
        call sax_error(fx, error_handler)
      else
        call sax_error(fx, error_handler)
      endif
    else
      ! EOF of main file
      if (startInChardata_) then
        if (fx%well_formed) then
          if (fx%state==ST_CHAR_IN_CONTENT.and.associated(fx%token)) then
            if (size(fx%token)>0.and.present(characters_handler)) &
              call characters_handler(str_vs(fx%token))
            ! No need for check on parser stop, we finish here anyway
          endif
        else
          if (present(error_handler)) &
            call error_handler("Ill-formed XML fragment")
        endif
      elseif (fx%well_formed.and.fx%state==ST_MISC) then
        if (present(endDocument_handler)) &
          call endDocument_handler()
        ! No need for check on parser stop, we finish here anyway
      else
        call add_error(fx%error_stack, "File is not well-formed")
        call sax_error(fx, error_handler)
      endif
    endif

  contains

    subroutine open_tag
      ! Are there any default values missing?
      if (validCheck) then
        elem => get_element(fx%xds%element_list, str_vs(fx%name))
        if (associated(elem)) &
          call checkImplicitAttributes(elem, fx%attributes)
        ! FIXME and also check that attribute declarations fit the ATTLIST
        ! FIXME and if we read external subset, is this element declared ok
        elem => get_element(fx%xds%element_list, get_top_elstack(fx%elstack))
        ! This will return null anyway if we are opening root element
        if (associated(elem)) then
          if (elem%empty) then
            call add_error(fx%error_stack, "Content inside empty element")
          endif
          ! FIXME and ideally do a proper check of is this element allowed here
        endif
      endif
      ! Check for namespace changes
      if (namespaces_) then
        call checkNamespaces(fx%attributes, fx%nsDict, &
        len(fx%elstack), fx%xds, namespace_prefixes_, xmlns_uris_, &
        fx%error_stack, startInCharData_, &
        startPrefixMapping_handler, endPrefixMapping_handler)
        if (fx%state==ST_STOP) return
      endif
      if (in_error(fx%error_stack)) return
      call checkXmlAttributes
      if (in_error(fx%error_stack)) return
      if (namespaces_.and.getURIofQName(fx,str_vs(fx%name))==invalidNS) then
        ! no namespace was found for the current element
        if (.not.startInCharData_) then
          ! but we ignore this if we are parsing an entity through DOM
          call add_error(fx%error_stack, "No namespace found for current element")
          return
        elseif (present(startElement_handler)) then
          ! Record it as having an empty URI
          call startElement_handler("", &
            getlocalNameofQName(str_vs(fx%name)), &
            str_vs(fx%name), fx%attributes)
          if (fx%state==ST_STOP) return
        endif
      elseif (namespaces_) then
        ! Normal state of affairs
        if (present(startElement_handler)) then
          call startElement_handler(getURIofQName(fx, str_vs(fx%name)), &
          getlocalNameofQName(str_vs(fx%name)), &
          str_vs(fx%name), fx%attributes)
          if (fx%state==ST_STOP) return
        endif
      else
        ! Non-namespace aware processing
        if (present(startElement_handler)) then
          call startElement_handler("", "", &
          str_vs(fx%name), fx%attributes)
          if (fx%state==ST_STOP) return
        endif
      endif
      call push_elstack(str_vs(fx%name), fx%elstack)
      call reset_dict(fx%attributes)
      fx%wf_stack(1) = fx%wf_stack(1) + 1
    end subroutine open_tag

    subroutine close_tag
      fx%wf_stack(1) = fx%wf_stack(1) - 1
      if (fx%wf_stack(1)<0) then
        call add_error(fx%error_stack, &
          'Ill-formed entity')
        return
      endif
      if (str_vs(fx%name)/=pop_elstack(fx%elstack)) then
        call add_error(fx%error_stack, "Mismatching close tag - expecting "//str_vs(fx%name))
        return
      endif
      if (present(endElement_handler)) then
        if (namespaces_.and.getURIofQName(fx,str_vs(fx%name))==invalidNS) then
          ! no namespace was found for the current element, we must be
          ! closing inside a DOM entity.
          ! Record it as having an empty URI
          call endElement_handler("", &
            getlocalNameofQName(str_vs(fx%name)), &
            str_vs(fx%name))
        elseif (namespaces_) then
          ! Normal state of affairs
          call endElement_handler(getURIofQName(fx, str_vs(fx%name)), &
            getlocalnameofQName(str_vs(fx%name)), &
            str_vs(fx%name))
        else
          ! Non-namespace-aware processing:
          call endElement_handler("", "", &
            str_vs(fx%name))
        endif
        if (fx%state==ST_STOP) return
      endif
      if (namespaces_) then
        call checkEndNamespaces(fx%nsDict, len(fx%elstack), &
        endPrefixMapping_handler)
        if (fx%state==ST_STOP) return
      endif
    end subroutine close_tag

    subroutine add_entity
      !Parameter or General Entity?
      if (pe) then
        !Does entity with this name exist?
        if (.not.existing_entity(fx%xds%PEList, str_vs(fx%name))) then
          ! Internal or external?
          if (associated(fx%attname)) then ! it's internal
            call register_internal_PE(fx%xds, &
              name=str_vs(fx%name), text=str_vs(fx%attname))
            ! FIXME need to expand value here before reporting ...
            if (present(internalEntityDecl_handler)) then
              call internalEntityDecl_handler('%'//str_vs(fx%name), str_vs(fx%attname))
              if (fx%state==ST_STOP) return
            endif
          else ! PE can't have Ndata declaration
            URIref => parseURI(str_vs(fx%systemId))
            if (.not.associated(URIref)) then
              call add_error(fx%error_stack, "Invalid URI specified for SYSTEM")
            elseif (hasFragment(URIref)) then
              call add_error(fx%error_stack, "Fragment not permitted on SYSTEM URI")
              call destroyURI(URIref)
            else
              newURI => rebaseURI(fb%f(1)%baseURI, URIref)
              if (associated(fx%publicId)) then
                call register_external_PE(fx%xds, name=str_vs(fx%name), &
                  systemId=expressURI(newURI), &
                  publicId=str_vs(fx%publicId))
                if (present(externalEntityDecl_handler)) &
                  call externalEntityDecl_handler('%'//str_vs(fx%name), &
                  systemId=expressURI(URIref), publicId=str_vs(fx%publicId))
              else
                call register_external_PE(fx%xds, name=str_vs(fx%name), &
                  systemId=expressURI(newURI))
                if (present(externalEntityDecl_handler)) &
                  call externalEntityDecl_handler('%'//str_vs(fx%name), &
                  systemId=expressURI(URIref))
              endif
              call destroyURI(URIref)
              call destroyURI(newURI)
            endif
          endif
          ! else we ignore it
        endif
      else !It's a general entity
        if (.not.existing_entity(fx%xds%entityList, str_vs(fx%name))) then
          ! Internal or external?
          if (associated(fx%attname)) then ! it's internal
            call register_internal_GE(fx%xds, name=str_vs(fx%name), &
              text=str_vs(fx%attname))
            if (present(internalEntityDecl_handler)) then
              call internalEntityDecl_handler(str_vs(fx%name),&
              str_vs(fx%attname))
              if (fx%state==ST_STOP) return
            endif
          else
            URIref => parseURI(str_vs(fx%systemId))
            if (.not.associated(URIref)) then
              call add_error(fx%error_stack, "Invalid URI specified for SYSTEM")
            elseif (hasFragment(URIref)) then
              call add_error(fx%error_stack, "Fragment not permitted on SYSTEM URI")
              call destroyURI(URIref)
            else
              newURI => rebaseURI(fb%f(1)%baseURI, URIref)
              if (associated(fx%publicId).and.associated(fx%Ndata)) then
                call register_external_GE(fx%xds, name=str_vs(fx%name), &
                  systemId=expressURI(newURI), publicId=str_vs(fx%publicId), &
                  notation=str_vs(fx%Ndata))
                if (present(unparsedEntityDecl_handler)) &
                  call unparsedEntityDecl_handler(str_vs(fx%name), &
                  systemId=expressURI(URIref), publicId=str_vs(fx%publicId), &
                  notation=str_vs(fx%Ndata))
              elseif (associated(fx%Ndata)) then
                call register_external_GE(fx%xds, name=str_vs(fx%name), &
                  systemId=expressURI(newURI), notation=str_vs(fx%Ndata))
                if (present(unparsedEntityDecl_handler)) &
                  call unparsedEntityDecl_handler(str_vs(fx%name), publicId="", &
                  systemId=expressURI(URIref), notation=str_vs(fx%Ndata))
              elseif (associated(fx%publicId)) then
                call register_external_GE(fx%xds, name=str_vs(fx%name), &
                  systemId=expressURI(newURI), publicId=str_vs(fx%publicId))
                if (present(externalEntityDecl_handler)) &
                  call externalEntityDecl_handler(str_vs(fx%name), &
                  systemId=expressURI(URIref), publicId=str_vs(fx%publicId))
              else
                call register_external_GE(fx%xds, name=str_vs(fx%name), &
                  systemId=expressURI(newURI))
                if (present(externalEntityDecl_handler)) &
                  call externalEntityDecl_handler(str_vs(fx%name), &
                  systemId=expressURI(URIref))
              endif
              call destroyURI(URIref)
              call destroyURI(newURI)
            endif
          endif
        endif
      endif
    end subroutine add_entity

    function NotCDataNormalize(s1) result(s2)
      character(len=*), intent(in) :: s1
      character(len=len(s1)) :: s2

      integer :: i, i2
      logical :: w

      i2 = 1
      w = .true.
      do i = 1, len(s1)
        if (w.and.(verify(s1(i:i),XML_WHITESPACE)==0)) cycle
        w = .false.
        s2(i2:i2) = s1(i:i)
        i2 = i2 + 1
        if (verify(s1(i:i),XML_WHITESPACE)==0) w = .true.
      enddo
      s2(i2:) = ''
    end function NotCDataNormalize

    subroutine checkImplicitAttributes(elem, dict)
      type(element_t), pointer :: elem
      type(dictionary_t), intent(inout) :: dict

      integer :: i
      type(string_list) :: default_atts

      default_atts = get_default_atts(elem%attlist)
      do i = 1, size(default_atts%list), 2
        if (.not.has_key(dict, str_vs(default_atts%list(i)%s))) then
          call add_item_to_dict(dict, str_vs(default_atts%list(i)%s), &
            str_vs(default_atts%list(i+1)%s), specified=.false.)
        endif
      enddo
      call destroy_string_list(default_atts)

    end subroutine checkImplicitAttributes

    subroutine checkXMLAttributes
      ! This must be done with the name of the attribute,
      ! not the nsURI/localname pair, in case we are
      ! processing for a non-namespace aware application
      if (has_key(fx%attributes, 'xml:space')) then
        if (get_value(fx%attributes, 'xml:space')/='default' &
          .and. get_value(fx%attributes, 'xml:space')/='preserve') then
          call add_error(fx%error_stack, 'Illegal value of xml:space attribute')
        endif
      endif
      ! FIXME
      !if (has_key(fx%attributes, 'xml:id')) then
      ! must be an NCName
      ! must be unique ...
      !endif
      !if (has_key(fx%attributes, 'xml:base')) then
      !   We never care about this at the SAX level; except
      !   that it must be a valid URI when we can check that.
      !   FIXME check valid URI
      !endif
      !if (has_key(fx%attributes, 'xml:lang')) then
      !   We never care about this at the SAX level.
      !endif
    end subroutine checkXMLAttributes
  end subroutine sax_parse


  subroutine sax_error(fx, error_handler)
    type(sax_parser_t), intent(inout) :: fx
    optional :: error_handler
    interface
      subroutine error_handler(msg)
        character(len=*), intent(in)     :: msg
      end subroutine error_handler
    end interface

    character, dimension(:), pointer :: errmsg

    integer :: i, m, n, n_err
    n = size(fx%error_stack%stack)
    n_err = n

    do i = 1, n
      n_err = n_err + size(fx%error_stack%stack(i)%msg) ! + spaces + size of entityref
    enddo
    allocate(errmsg(n_err))
    errmsg = ''
    n = 1
    do i = 1, size(fx%error_stack%stack)
      m = size(fx%error_stack%stack(i)%msg)
      errmsg(n:n+m-1) = fx%error_stack%stack(i)%msg
      errmsg(n+m:n+m) = " "
      n = n + m + 1
    enddo
    ! FIXME put location information in here
    if (present(error_handler)) then
      call error_handler(str_vs(errmsg))
      deallocate(errmsg)
      if (fx%state==ST_STOP) return
    else
      call FoX_error(str_vs(errmsg))
    endif

  end subroutine sax_error

  pure function URIlength(fx, qname) result(l_u)
    type(sax_parser_t), intent(in) :: fx
    character(len=*), intent(in) :: qName
    integer :: l_u
    integer :: n
    n = index(QName, ':')
    if (n > 0) then
      l_u = len(getnamespaceURI(fx%nsDict, QName(1:n-1)))
    else
      l_u = len(getnamespaceURI(fx%nsDict))
    endif
  end function URIlength

  pure function getURIofQName(fx, qname) result(URI)
    type(sax_parser_t), intent(in) :: fx
    character(len=*), intent(in) :: qName
    character(len=URIlength(fx, qname)) :: URI

    integer :: n
    n = index(QName, ':')
    if (n > 0) then
      URI = getnamespaceURI(fx%nsDict, QName(1:n-1))
    else
      URI = getnamespaceURI(fx%nsDict)
    endif

  end function getURIofQName

  pure function getLocalNameofQName(qname) result(localName)
    character(len=*), intent(in) :: qName
    character(len=len(QName)-index(QName,':')) :: localName

    localName = QName(index(QName,':')+1:)
  end function getLocalNameofQName

end module m_sax_parser
