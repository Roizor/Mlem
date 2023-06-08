//
//  Opened Post.swift
//  Mlem
//
//  Created by David Bureš on 25.03.2022.
//

import SwiftUI

internal enum PossibleStyling
{
    case bold, italics
}

struct PostExpanded: View
{
    @AppStorage("defaultCommentSorting") var defaultCommentSorting: CommentSortTypes = .top

    @EnvironmentObject var appState: AppState

    @StateObject var commentTracker: CommentTracker = .init()
    @StateObject var commentReplyTracker: CommentReplyTracker = .init()

    @State var account: SavedAccount

    @State var postTracker: PostTracker

    var post: Post

    @State private var sortSelection = 0

    @State private var commentSortingType: CommentSortTypes = .top

    @FocusState var isReplyFieldFocused
    
    @Binding var feedType: FeedType

    @State private var textFieldContents: String = ""
    @State private var replyingToCommentID: Int? = nil

    @State private var isInTheMiddleOfStyling: Bool = false
    @State private var isPostingComment: Bool = false

    @State private var viewID: UUID = UUID()

    var body: some View
    {
        ScrollView
        {
            PostItem(postTracker: postTracker, post: post, isExpanded: true, isInSpecificCommunity: true, account: account, feedType: $feedType)

            if commentTracker.isLoading
            {
                ProgressView("Loading comments…")
                    .task(priority: .userInitiated)
                    {
                        if post.numberOfComments != 0
                        {
                            await loadComments()
                        }
                        else
                        {
                            commentTracker.isLoading = false
                        }
                    }
                    .onAppear
                    {
                        commentSortingType = defaultCommentSorting
                    }
            }
            else
            {
                if commentTracker.comments.count == 0
                { // If there are no comments, just don't show anything
                    VStack(spacing: 2)
                    {
                        VStack(spacing: 5)
                        {
                            Image(systemName: "binoculars")
                                
                            Text("No comments to be found")
                        }
                        Text("Why not post the first one?")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    .padding()
                }
                else
                { // Otherwise we'll have to do some actual work
                    LazyVStack(alignment: .leading, spacing: 15)
                    {
                        ForEach(commentTracker.comments)
                        { comment in
                            CommentItem(account: account, comment: comment)
                        }
                    }
                    .environmentObject(commentTracker)
                }
            }
        }
        .environmentObject(commentReplyTracker)
        .navigationBarTitle(post.community.name, displayMode: .inline)
        .safeAreaInset(edge: .bottom)
        {
            VStack
            {
                if commentReplyTracker.commentToReplyTo != nil
                {
                    HStack(alignment: .top)
                    {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .center, spacing: 2) {
                                Text("Replying to \(commentReplyTracker.commentToReplyTo!.author.name):")
                                    .font(.caption)
                                
                            #warning("TODO: Add the user avatar")
                                // UserProfileLink(shouldShowUserAvatars: true, user: commentReplyTracker.commentToReplyTo!.author)
                            }
                            .foregroundColor(.secondary)
                            
                            Text(commentReplyTracker.commentToReplyTo!.content)
                                .font(.system(size: 16))
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    
                    Divider()
                }
                
                HStack(alignment: .center, spacing: 10)
                {
                    TextField("Reply to post", text: $textFieldContents, prompt: Text("Commenting as \(account.username):"), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($isReplyFieldFocused)

                    if !textFieldContents.isEmpty
                    {
                        if !isPostingComment
                        {
                            Button
                            {
                                if commentReplyTracker.commentToReplyTo == nil
                                {
                                    Task(priority: .userInitiated)
                                    {
                                        isPostingComment = true
                                        
                                        print("Will post comment")
                                        
                                        defer
                                        {
                                            isPostingComment = false
                                        }
                                        
                                        do
                                        {
                                            try await postComment(to: post, commentContents: textFieldContents, commentTracker: commentTracker, account: account, appState: appState)
                                            
                                            isReplyFieldFocused = false
                                            textFieldContents = ""
                                        }
                                        catch let commentPostingError
                                        {
                                            
                                            appState.alertTitle = "Couldn't post comment"
                                            appState.alertMessage = "An error occured when posting the comment.\nTry again later, or restart Mlem."
                                            appState.isShowingAlert.toggle()
                                            
                                            print("Failed while posting error: \(commentPostingError)")
                                        }
                                    }
                                }
                                else
                                {
                                    Task(priority: .userInitiated) {
                                        isPostingComment = true
                                        
                                        print("Will post reply")
                                        
                                        defer
                                        {
                                            isPostingComment = false
                                        }
                                        
                                        do
                                        {
                                            try await postComment(to: commentReplyTracker.commentToReplyTo!, post: post, commentContents: textFieldContents, commentTracker: commentTracker, account: account, appState: appState)
                                            
                                            commentReplyTracker.commentToReplyTo = nil
                                            isReplyFieldFocused = false
                                            textFieldContents = ""
                                        }
                                        catch let replyPostingError
                                        {                                            
                                            print("Failed while posting response: \(replyPostingError)")
                                        }
                                    }
                                }
                                
                            } label: {
                                Image(systemName: "paperplane")
                            }
                        }
                        else
                        {
                            ProgressView()
                        }
                    }
                }
                .padding()

                Divider()
            }
            .background(.regularMaterial)
            .animation(.interactiveSpring(response: 0.4, dampingFraction: 1, blendDuration: 0.4), value: textFieldContents)
            .onChange(of: commentReplyTracker.commentToReplyTo) { newValue in
                if newValue != nil
                {
                    isReplyFieldFocused.toggle()
                }
            }
        }
        .toolbar
        {
            ToolbarItemGroup(placement: .navigationBarTrailing)
            {
                Menu
                {
                    Button
                    {
                        commentSortingType = .active
                    } label: {
                        Label("Active", systemImage: "bubble.left.and.bubble.right")
                    }

                    Button
                    {
                        commentSortingType = .new
                    } label: {
                        Label("New", systemImage: "sun.max")
                    }

                    Button
                    {
                        commentSortingType = .top
                    } label: {
                        Label("Top", systemImage: "calendar.day.timeline.left")
                    }

                } label: {
                    switch commentSortingType
                    {
                    case .new:
                        Label("New", systemImage: "sun.max")
                    case .top:
                        Label("Top", systemImage: "calendar.day.timeline.left")
                    case .active:
                        Label("Active", systemImage: "bubble.left.and.bubble.right")
                    }
                }
            }

            ToolbarItemGroup(placement: .keyboard)
            {
                Spacer()

                Button
                {
                    isReplyFieldFocused = false
                    
                    if commentReplyTracker.commentToReplyTo != nil
                    {
                        commentReplyTracker.commentToReplyTo = nil
                    }
                } label: {
                    Text("Cancel")
                }
            }
        }
        .refreshable
        {
            Task(priority: .userInitiated)
            {
                commentTracker.comments = .init()

                await loadComments()
            }
        }
        .onChange(of: commentSortingType)
        { newSortingType in
            withAnimation(.easeIn(duration: 0.4))
            {
                commentTracker.comments = sortComments(commentTracker.comments, by: newSortingType)
            }
        }
    }

    internal func loadComments() async
    {
        commentTracker.isLoading = true

        var parsedComments: [Comment] = .init()
        
        defer
        {
            commentTracker.isLoading = false
            
            parsedComments = .init()
        }
        
        do
        {
            let commentResponse: String = try await sendGetCommand(appState: appState, account: account, endpoint: "comment/list", parameters: [
                URLQueryItem(name: "max_depth", value: "15"),
                URLQueryItem(name: "post_id", value: "\(post.id)"),
                URLQueryItem(name: "type_", value: "All")
            ])
            
            print("Comment response: \(commentResponse)")
            
            do
            {
                parsedComments = try await parseComments(commentResponse: commentResponse, instanceLink: account.instanceLink)
                
                commentTracker.comments = sortComments(parsedComments, by: defaultCommentSorting)
            }
            catch let commentParsingError
            {
                
                appState.alertTitle = "Couldn't decode updated comments"
                appState.alertMessage = "Try manually refreshing the comments."
                appState.isShowingAlert.toggle()
                
                print("Failed while parsing comments: \(commentParsingError)")
            }
        }
        catch let commentLoadingError
        {
            
            appState.alertTitle = "Couldn't load new comments"
            appState.alertMessage = "The Lemmy server you're connected to might be overloaded."
            appState.isShowingAlert.toggle()
            
            print("Failed while loading comments: \(commentLoadingError)")
        }
    }

    private func sortComments(_ comments: [Comment], by sort: CommentSortTypes) -> [Comment]
    {
        let sortedComments: [Comment]
        switch sort
        {
        case .new:
            sortedComments = comments.sorted(by: { $0.published > $1.published })
        case .top:
            sortedComments = comments.sorted(by: { $0.score > $1.score })
        case .active:
            sortedComments = comments.sorted(by: { $0.children.count > $1.children.count })
        }

        return sortedComments.map
        { comment in
            var newComment = comment
            newComment.children = sortComments(comment.children, by: sort)
            return newComment
        }
    }
}
