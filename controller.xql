xquery version "3.0";
import module namespace global="http://syriaca.org/global" at "modules/lib/global.xqm";
declare variable $exist:path external;
declare variable $exist:resource external;
declare variable $exist:controller external;
declare variable $exist:prefix external;
declare variable $exist:root external;

(: Get variables for Srophe collections. :)
declare variable $exist:record-uris  := 
    distinct-values(for $collection in $global:get-config//repo:collection
    let $short-path := replace($collection/@record-URI-pattern,$global:base-uri,'')
    return $short-path)      
; 

(: Send to content negotiation:)
declare function local:content-negotiation($exist:path, $exist:resource){
    if(starts-with($exist:resource, ('search','browse'))) then
        let $format := request:get-parameter('format', '')
        return 
        <dispatch xmlns="http://exist.sourceforge.net/NS/exist">        
            <forward url="{$exist:controller}/modules/content-negotiation/content-negotiation.xql"/>
            <add-parameter name="format" value="{$format}"/>
        </dispatch>
    else
        let $id := if($exist:resource = ('tei','xml','txt','pdf','json','geojson','kml','jsonld','rdf','ttl','atom')) then
                        tokenize(replace($exist:path,'/tei|/xml|/txt|/pdf|/json|/geojson|/kml|/jsonld|/rdf|/ttl|/atom',''),'/')[last()]
                   else replace(xmldb:decode($exist:resource), "^(.*)\..*$", "$1")
        let $record-uri-root := substring-before($exist:path,$id)
        let $id := if($global:get-config//repo:collection[ends-with(@record-URI-pattern, $record-uri-root)]) then
                        concat($global:get-config//repo:collection[ends-with(@record-URI-pattern, $record-uri-root)][1]/@record-URI-pattern,$id)
                   else $id
        let $html-path := concat($global:get-config//repo:collection[ends-with(@record-URI-pattern, $record-uri-root)][1]/@app-root,'record.html')
        let $format := if($exist:resource = ('tei','xml','txt','pdf','json','geojson','kml','jsonld','rdf','ttl','atom')) then
                            $exist:resource
                       else if(request:get-parameter('format', '') != '') then request:get-parameter('format', '')                            
                       else fn:tokenize($exist:resource, '\.')[fn:last()]
        return 
            if($global:get-config//repo:collection[ends-with(@record-URI-pattern, $record-uri-root)]) then 
                <dispatch xmlns="http://exist.sourceforge.net/NS/exist">        
                    <forward url="{$exist:controller}/modules/content-negotiation/content-negotiation.xql">
                        <add-parameter name="id" value="{$id}"/>
                        <add-parameter name="format" value="{$format}"/>
                    </forward>
                </dispatch>
            else 
                <dispatch xmlns="http://exist.sourceforge.net/NS/exist">        
                    <forward url="{$exist:root}/{$exist:path}"/>
                </dispatch>
};

(: Get variables for Srophe collections. :)
declare variable $exist:collection-uris  := 
    distinct-values(for $collection in $global:get-config//repo:collection
    let $short-path := replace($collection/@app-root,$global:base-uri,'')
    return concat('/',$short-path,'/'))    
; 

(: White list of html pages :)
declare variable $exist:white-list  := 
    distinct-values(for $page in $global:get-config//repo:white-list/repo:page/text()
    return $page)    
;

(: Used to test vars
<div>
    <p>$exist:path: {$exist:path}</p>
    <p>$exist:resource: {$exist:resource}</p>
    <p>$exist:controller: {$exist:controller}</p>
    <p>$exist:prefix: {$exist:prefix}</p>
    <p>$exist:root: {$exist:root}</p>
    <p>Srophe record uris: {$exist:record-uris}</p>
    <p>Srophe coleection uris: {$exist:collection-uris}</p>
</div>
:)


if ($exist:path eq '') then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="{request:get-uri()}/"/>
    </dispatch>

(: Resource paths starting with $app-root are resolved relative to app :)
else if (contains($exist:path, "/$app-root/")) then
        <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
            <forward url="{concat($exist:controller,'/', substring-after($exist:path, '/$app-root/'))}">
                <set-header name="Cache-Control" value="max-age=3600, must-revalidate"/>
            </forward>
        </dispatch>        

(: Resource paths starting with $shared are loaded from the shared-resources app :)
else if (contains($exist:path, "/$shared/")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="/shared-resources/{substring-after($exist:path, '/$shared/')}">
            <set-header name="Cache-Control" value="max-age=3600, must-revalidate"/>
        </forward>
    </dispatch>

(: Passes any api requests to volume index :)  
else if (contains($exist:path,'/volume/')) then
    let $id := replace(xmldb:decode($exist:resource), "^(.*)\..*$", "$1")
    let $record-uri-root := replace($exist:path,$exist:resource,'')
    let $html-path := '/volumes.html'
    return 
        <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
            <forward url="{$exist:controller}{$html-path}"></forward>
                <view>
                    <forward url="{$exist:controller}/modules/view.xql">
                       <add-parameter name="volume" value="{$id}"/>
                    </forward>
                </view>
                <error-handler>
                    <forward url="{$exist:controller}/error-page.html" method="get"/>
                    <forward url="{$exist:controller}/modules/view.xql"/>
                </error-handler>
         </dispatch> 
(: Passes data to content negotiation module:)
else if(request:get-parameter('format', '') != '' and request:get-parameter('format', '') != 'html') then
    local:content-negotiation($exist:path, $exist:resource)
else if(ends-with($exist:path,('/tei','/xml','/txt','/pdf','/json','/geojson','/kml','/jsonld','/rdf','/ttl','/atom'))) then
    local:content-negotiation($exist:path, $exist:resource)
else if(ends-with($exist:resource,('.tei','.xml','.txt','.pdf','.json','.geojson','.kml','.jsonld','.rdf','.ttl','.atom'))) then
    local:content-negotiation($exist:path, $exist:resource)

(: Checks for any record uri patterns as defined in repo.xml :)    
else if(replace($exist:path, $exist:resource,'') =  ($exist:record-uris) or ends-with($exist:path, ("/atom","/tei","/rdf","/txt","/ttl",'.tei','.atom','.rdf','.ttl',".txt"))) then
    (: Sends to restxql to handle /atom, /tei,/rdf:)
    if (ends-with($exist:path, ("/atom","/tei","/rdf","/ttl","/txt",".tei",".atom",".rdf",".ttl",".txt"))) then
      let $path := 
            if(ends-with($exist:path, (".atom",".tei",".rdf",".ttl",".txt"))) then 
                replace($exist:path, "\.(atom|tei|rdf|ttl|txt)", "/$1")
            else $exist:path
        return 
            <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
                <forward url="{concat('/restxq/hugoye', $path)}" absolute="yes"/>
            </dispatch>
    (: Special handling for collections 
    with app-root that matches record-URI-pattern sends html pages to html, 
    others are assumed to be records :)
    else if($exist:resource = ($exist:white-list)) then 
     <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
           <view>
               <forward url="{$exist:controller}/modules/view.xql"/>
           </view>
   		<error-handler>
   			<forward url="{$exist:controller}/error-page.html" method="get"/>
   			<forward url="{$exist:controller}/modules/view.xql"/>
   		</error-handler>
       </dispatch>
    (: parses out record id to be passed to correct collection view, based on values in repo.xml :)       
    else if($exist:resource = '') then 
        <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
            <redirect url="index.html"/>
        </dispatch>
    else 
        let $id := replace(xmldb:decode($exist:resource), "^(.*)\..*$", "$1")
        let $record-uri-root := replace($exist:path,$exist:resource,'')
        let $html-path := concat('/',$global:get-config//repo:collection[ends-with(@record-URI-pattern, $record-uri-root)][1]/@app-root,'/record.html')
        return 
        <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
            <forward url="{$exist:controller}{$html-path}"></forward>
                <view>
                    <forward url="{$exist:controller}/modules/view.xql">
                       <add-parameter name="id" value="{$id}"/>
                    </forward>
                </view>
                <error-handler>
                    <forward url="{$exist:controller}/error-page.html" method="get"/>
                    <forward url="{$exist:controller}/modules/view.xql"/>
                </error-handler>
         </dispatch> 

(: Passes any api requests to restxq:)    
else if (contains($exist:path,'/api/')) then
  if (ends-with($exist:path,"/")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="/api-documentation/index.html"/>
    </dispatch> 
   else if($exist:resource = 'index.html') then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="/api-documentation/index.html"/>
    </dispatch>
    else if($exist:resource = 'oai') then
     <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{replace($exist:path,'/api/oai','/hugoye/modules/oai.xql')}"/>
     </dispatch>
    else
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{concat('/restxq/hugoye', $exist:path)}" absolute="yes"/>
    </dispatch>

else if ($exist:resource eq '' or ends-with($exist:path,"/")) then 
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="index.html"/>
    </dispatch>
    
(: Sends all other html pages through eXist templating module for processing. :)    
else if (ends-with($exist:resource, ".html")) then
    (: the html page is run through view.xql to expand templates :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <view>
            <forward url="{$exist:controller}/modules/view.xql"/>
        </view>
		<error-handler>
			<forward url="{$exist:controller}/error-page.html" method="get"/>
			<forward url="{$exist:controller}/modules/view.xql"/>
		</error-handler>
    </dispatch>

(: Redirects paths with directory, and no trailing slash to index.html in that directory :)    
else if (matches($exist:resource, "^([^.]+)$")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="{concat($exist:path,'/index.html')}"/>
    </dispatch>         
else
    (: everything else is passed through :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <cache-control cache="yes"/>
    </dispatch>