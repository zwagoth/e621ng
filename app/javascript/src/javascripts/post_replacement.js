import Utility from './utility'

let PostReplacement = {};

PostReplacement.initialize_all = function () {
  $(".replacement-approve-action").on("click", e => {
    const target = $(e.target);
    e.preventDefault();
    PostReplacement.approve(target.data("replacement-id"), target.data("penalize"));
  });
  $(".replacement-reject-action").on("click", e => {
    e.preventDefault();
    PostReplacement.reject($(e.target).data("replacement-id"));
  });
  $(".replacement-promote-action").on("click", e => {
    e.preventDefault();
    PostReplacement.promote($(e.target).data("replacement-id"));
  });
  $(".replacement-toggle-penalize-action").on("click", e => {
    e.preventDefault();
    PostReplacement.toggle_penalize($(e.target).data("replacement-id"));
  });
};

PostReplacement.approve = function (id, penalize_current_uploader) {
  $.ajax({
    type: "PUT",
    url: `/post_replacements/${id}/approve.json`,
    data: {
      penalize_current_uploader: penalize_current_uploader
    },
    dataType: 'json'
  }).done(function () {
    Utility.notice("Post Replacement accepted");
  }).fail(function (data, status, xhr) {
    Utility.error(data.responseText);
  });
};

PostReplacement.reject = function (id) {
  $.ajax({
    type: "PUT",
    url: `/post_replacements/${id}/reject.json`,
    dataType: 'json'
  }).done(function () {
    Utility.notice("Post Replacement rejected");
  }).fail(function (data, status, xhr) {
    Utility.error(data.responseText);
  });
}

PostReplacement.promote = function (id) {
  $.ajax({
    type: "POST",
    url: `/post_replacements/${id}/promote.json`,
    dataType: 'json'
  }).done(function (data) {
    Utility.notice(`Replacement promoted to post #${data.post.id}`)
  }).fail(function (data, status, xhr) {
    Utility.error(data.responseText);
  });
}

PostReplacement.toggle_penalize = function (id) {
  $.ajax({
    type: "PUT",
    url: `/post_replacements/${id}/toggle_penalize.json`,
    dataType: 'json'
  }).done(function (data) {
    Utility.notice("User upload limit updated");
  }).fail(function (data, status, xhr) {
    Utility.error(data.responseText);
  });
}

$(function () {
  if ($("#c-post-replacements").length)
    PostReplacement.initialize_all();
});


export default PostReplacement
