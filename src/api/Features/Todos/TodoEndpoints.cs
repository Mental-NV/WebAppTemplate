namespace Api.Features.Todos;

public static class TodoEndpoints
{
    public static RouteGroupBuilder MapTodosEndpoints(this RouteGroupBuilder apiV1)
    {
        var group = apiV1.MapGroup("/todos")
            .WithTags("Todos")
            .RequireAuthorization();

        group.MapGet("/", ListTodos.Handle);
        group.MapGet("/{id:int}", GetTodo.Handle);

        group.MapPost("/", CreateTodo.Handle);
        group.MapPut("/{id:int}", UpdateTodo.Handle);

        group.MapDelete("/{id:int}", DeleteTodo.Handle);

        return apiV1;
    }
}
