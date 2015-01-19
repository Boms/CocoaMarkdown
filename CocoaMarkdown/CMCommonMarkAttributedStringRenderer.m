//
//  CMCommonMarkAttributedStringRenderer.m
//  CocoaMarkdown
//
//  Created by Indragie on 1/14/15.
//  Copyright (c) 2015 Indragie Karunaratne. All rights reserved.
//

#import "CMCommonMarkAttributedStringRenderer.h"
#import "CMAttributeRun.h"
#import "CMCascadingAttributeStack.h"
#import "CMStack.h"
#import "CMHTMLElementTransformer.h"
#import "CMHTMLElement.h"
#import "CMHTMLUtilities.h"
#import "CMTextAttributes.h"
#import "CMNode.h"
#import "CMParser.h"

#import "Ono.h"

@interface CMCommonMarkAttributedStringRenderer () <CMParserDelegate>
@end

@implementation CMCommonMarkAttributedStringRenderer {
    CMDocument *_document;
    CMTextAttributes *_attributes;
    CMCascadingAttributeStack *_attributeStack;
    CMStack *_HTMLStack;
    NSMutableDictionary *_tagNameToTransformerMapping;
    NSMutableAttributedString *_buffer;
    NSAttributedString *_attributedString;
}

- (instancetype)initWithDocument:(CMDocument *)document attributes:(CMTextAttributes *)attributes
{
    if ((self = [super init])) {
        _document = document;
        _attributes = attributes;
        _tagNameToTransformerMapping = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)registerHTMLElementTransformer:(id<CMHTMLElementTransformer>)transformer
{
    NSParameterAssert(transformer);
    _tagNameToTransformerMapping[[transformer.class tagName]] = transformer;
}

- (NSAttributedString *)render
{
    if (_attributedString == nil) {
        _attributeStack = [[CMCascadingAttributeStack alloc] init];
        _HTMLStack = [[CMStack alloc] init];
        _buffer = [[NSMutableAttributedString alloc] init];
        
        CMParser *parser = [[CMParser alloc] initWithDocument:_document delegate:self];
        [parser parse];
        
        _attributedString = [_buffer copy];
        _attributeStack = nil;
        _HTMLStack = nil;
        _buffer = nil;
    }
    
    return _attributedString;
}

#pragma mark - CMParserDelegate

- (void)parserDidStartDocument:(CMParser *)parser
{
    [_attributeStack push:CMDefaultAttributeRun(_attributes.textAttributes)];
}

- (void)parserDidEndDocument:(CMParser *)parser
{
    CFStringTrimWhitespace((__bridge CFMutableStringRef)_buffer.mutableString);
}

- (void)parser:(CMParser *)parser foundText:(NSString *)text
{
    CMHTMLElement *element = [_HTMLStack peek];
    if (element != nil) {
        [element.buffer appendString:text];
    } else {
        [self appendString:text];
    }
}

- (void)parser:(CMParser *)parser didStartHeaderWithLevel:(NSInteger)level
{
    [_attributeStack push:CMDefaultAttributeRun([_attributes attributesForHeaderLevel:level])];
}

- (void)parser:(CMParser *)parser didEndHeaderWithLevel:(NSInteger)level
{
    [self appendString:@"\n"];
    [_attributeStack pop];
}

- (void)parserDidStartParagraph:(CMParser *)parser
{
    [self appendLineBreakIfNotTightForNode:parser.currentNode];
}

- (void)parserDidEndParagraph:(CMParser *)parser
{
    [self appendLineBreakIfNotTightForNode:parser.currentNode];
}

- (void)parserDidStartEmphasis:(CMParser *)parser
{
    BOOL hasExplicitFont = _attributes.emphasisAttributes[NSFontAttributeName] != nil;
    [_attributeStack push:CMTraitAttributeRun(_attributes.emphasisAttributes, hasExplicitFont ? 0 : CMFontTraitItalic)];
}

- (void)parserDidEndEmphasis:(CMParser *)parser
{
    [_attributeStack pop];
}

- (void)parserDidStartStrong:(CMParser *)parser
{
    BOOL hasExplicitFont = _attributes.strongAttributes[NSFontAttributeName] != nil;
    [_attributeStack push:CMTraitAttributeRun(_attributes.strongAttributes, hasExplicitFont ? 0 : CMFontTraitBold)];
}

- (void)parserDidEndStrong:(CMParser *)parse
{
    [_attributeStack pop];
}

- (void)parser:(CMParser *)parser didStartLinkWithURL:(NSURL *)URL title:(NSString *)title
{
    NSMutableDictionary *baseAttributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:URL, NSLinkAttributeName, nil];
#if !TARGET_OS_IPHONE
    if (title != nil) {
        baseAttributes[NSToolTipAttributeName] = title;
    }
#endif
    [baseAttributes addEntriesFromDictionary:_attributes.linkAttributes];
    [_attributeStack push:CMDefaultAttributeRun(baseAttributes)];
}

- (void)parser:(CMParser *)parser didEndLinkWithURL:(NSURL *)URL title:(NSString *)title
{
    [_attributeStack pop];
}

- (void)parser:(CMParser *)parser foundHTML:(NSString *)HTML
{
    NSString *tagName = CMTagNameFromHTMLTag(HTML);
    if (tagName.length != 0) {
        CMHTMLElement *element = [self newHTMLElementForTagName:tagName HTML:HTML];
        if (element != nil) {
            [self appendHTMLElement:element];
        }
    }
}

- (void)parser:(CMParser *)parser foundInlineHTML:(NSString *)HTML
{
    NSString *tagName = CMTagNameFromHTMLTag(HTML);
    if (tagName.length != 0) {
        CMHTMLElement *element = nil;
        if (CMIsHTMLVoidTagName(tagName)) {
            element = [self newHTMLElementForTagName:tagName HTML:HTML];
            if (element != nil) {
                [self appendHTMLElement:element];
            }
        } else if (CMIsHTMLClosingTag(HTML)) {
            if ((element = [_HTMLStack pop])) {
                NSAssert([element.tagName isEqualToString:tagName], @"Closing tag does not match opening tag");
                [element.buffer appendString:HTML];
                [self appendHTMLElement:element];
            }
        } else if (CMIsHTMLTag(HTML)) {
            element = [self newHTMLElementForTagName:tagName HTML:HTML];
            if (element != nil) {
                [_HTMLStack push:element];
            }
        }
    }
}

- (void)parser:(CMParser *)parser foundCodeBlock:(NSString *)code info:(NSString *)info
{
    [_attributeStack push:CMDefaultAttributeRun(_attributes.codeBlockAttributes)];
    [self appendString:[NSString stringWithFormat:@"\n\n%@\n\n", code]];
    [_attributeStack pop];
}

- (void)parser:(CMParser *)parser foundInlineCode:(NSString *)code
{
    [_attributeStack push:CMDefaultAttributeRun(_attributes.inlineCodeAttributes)];
    [self appendString:code];
    [_attributeStack pop];
}

- (void)parserFoundSoftBreak:(CMParser *)parser
{
    [self appendString:@"\n"];
}

- (void)parserFoundLineBreak:(CMParser *)parser
{
    [self appendString:@"\n"];
}

- (void)parserDidStartBlockQuote:(CMParser *)parser
{
    [_attributeStack push:CMDefaultAttributeRun(_attributes.blockQuoteAttributes)];
}

- (void)parserDidEndBlockQuote:(CMParser *)parser
{
    [_attributeStack pop];
}

- (void)parser:(CMParser *)parser didStartUnorderedListWithTightness:(BOOL)tight
{
    [_attributeStack push:CMDefaultAttributeRun(_attributes.unorderedListAttributes)];
    [self appendString:@"\n"];
}

- (void)parser:(CMParser *)parser didEndUnorderedListWithTightness:(BOOL)tight
{
    [_attributeStack pop];
}

- (void)parser:(CMParser *)parser didStartOrderedListWithStartingNumber:(NSInteger)num tight:(BOOL)tight
{
    [_attributeStack push:CMOrderedListAttributeRun(_attributes.orderedListAttributes, num)];
    [self appendString:@"\n"];
}

- (void)parser:(CMParser *)parser didEndOrderedListWithStartingNumber:(NSInteger)num tight:(BOOL)tight
{
    [_attributeStack pop];
}

- (void)parserDidStartListItem:(CMParser *)parser
{
    CMNode *node = parser.currentNode.parent;
    switch (node.listType) {
        case CMARK_NO_LIST:
            NSAssert(NO, @"Parent node of list item must be a list");
            break;
        case CMARK_BULLET_LIST: {
            [self appendString:@"\u2022 "];
            [_attributeStack push:CMDefaultAttributeRun(_attributes.unorderedListItemAttributes)];
            break;
        }
        case CMARK_ORDERED_LIST: {
            CMAttributeRun *parentRun = [_attributeStack peek];
            [self appendString:[NSString stringWithFormat:@"%ld. ", parentRun.orderedListItemNumber]];
            parentRun.orderedListItemNumber++;
            [_attributeStack push:CMDefaultAttributeRun(_attributes.orderedListItemAttributes)];
            break;
        }
        default:
            break;
    }
}

- (void)parserDidEndListItem:(CMParser *)parser
{
    [self appendString:@"\n"];
    [_attributeStack pop];
}

#pragma mark - Private

- (CMHTMLElement *)newHTMLElementForTagName:(NSString *)tagName HTML:(NSString *)HTML
{
    NSParameterAssert(tagName);
    id<CMHTMLElementTransformer> transformer = _tagNameToTransformerMapping[tagName];
    if (transformer != nil) {
        CMHTMLElement *element = [[CMHTMLElement alloc] initWithTransformer:transformer];
        [element.buffer appendString:HTML];
        return element;
    }
    return nil;
}

- (void)appendLineBreakIfNotTightForNode:(CMNode *)node
{
    CMNode *grandparent = node.parent.parent;
    if (!grandparent.listTight) {
        [self appendString:@"\n"];
    }
}

- (void)appendString:(NSString *)string
{
    NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:string attributes:_attributeStack.cascadedAttributes];
    [_buffer appendAttributedString:attrString];
}

- (void)appendHTMLElement:(CMHTMLElement *)element
{
    NSError *error = nil;
    ONOXMLDocument *document = [ONOXMLDocument HTMLDocumentWithString:element.buffer encoding:NSUTF8StringEncoding error:&error];
    if (document == nil) {
        NSLog(@"Error creating HTML document for buffer \"%@\": %@", element.buffer, error);
        return;
    }
    
    ONOXMLElement *XMLElement = document.rootElement[0][0];
    NSDictionary *attributes = _attributeStack.cascadedAttributes;
    NSAttributedString *attrString = [element.transformer attributedStringForElement:XMLElement attributes:attributes];
    
    if (attrString != nil) {
        CMHTMLElement *parentElement = [_HTMLStack peek];
        if (parentElement == nil) {
            [_buffer appendAttributedString:attrString];
        } else {
            [parentElement.buffer appendString:attrString.string];
        }
    }
}

@end